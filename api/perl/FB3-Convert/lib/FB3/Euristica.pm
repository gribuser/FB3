package FB3::Euristica;

use strict;
use Data::Dumper;
use utf8;
use WWW::Mechanize::PhantomJS;
use FB3::Convert;
use File::Copy;

sub new {
  my $class = shift;
  my $X = {};
  my %Args = @_;

  $X->{'verbose'}        = $Args{'verbose'};
  $X->{'ContentDir'}     = $Args{'ContentDir'};
  $X->{'DestinationDir'} = $Args{'DestinationDir'};
  $X->{'DebugPath'}      = $Args{'DebugPath'} || undef;
  $X->{'DebugPrefix'}    = $Args{'DebugPrefix'} || undef;

  if ($X->{'DebugPath'}) {
    mkdir $X->{'DebugPath'} or die $X->{'DebugPath'}." : $!" unless -d $X->{'DebugPath'};
    FB3::Convert::Msg($X, "Create euristica debug at $X->{'DebugPath'}\n");
  }

  my $PHJS_bin = $Args{'phjs'} || undef;

  my $mech = WWW::Mechanize::PhantomJS->new('launch_exe'=>$PHJS_bin);
  $X->{'MECH'} = $mech;

  return bless $X, $class;
}

sub CalculateLinks {
  my $X = shift;
  my %Args = @_;
  my $Files = $Args{'files'} || [];

  my $PHJS = $X->{'MECH'};
  my %Links;

  foreach my $File (@$Files) {
    $PHJS->get_local($File) or FB3::Convert::Error($X, "Can't open file for phantomjs ".$File." : ".$!);

    my $Links =  $PHJS->eval_in_page(<<'Links', 'Foobar/1.0');
(function(arguments){
  var TEXT_NODE = 3;
  var nodesBody = Array.prototype.slice.call(document.body.childNodes);
  var Ret = Array();

  NodeProc(nodesBody);

  function NodeProc(nodes) {
    nodes.forEach(function(node) {
      if (node.nodeType == TEXT_NODE) return;
      var childs = Array.prototype.slice.call(node.childNodes);
      NodeProc(childs);      
      if (node.nodeName.toLowerCase() == 'a' && node.href.match(/^file:\/\//)) {
        Ret.push(node.href);
      }
    });
  }

  return Ret;
})(arguments);
Links

    foreach my $Link ( @$Links ) {
      $Link =~ s/^file:\/\///;
      my ($LinkFile,$Anchor) = split /\#/, $Link;
      $Links{$LinkFile}->{$Anchor} = 1 if $Anchor;
    }

  }

  $X->{'LocalLinks'} = \%Links;

  return \%Links;
}

sub ParseFile {
  my $X = shift;
  my %Args = @_;

  FB3::Convert::Error($X, "Can't find file for parse or not defined 'file' param ".$Args{'file'}) if !defined $Args{'file'} || !-f $Args{'file'};
  $X->{'SrcFile'} = $Args{'file'};

  my $PHJS = $X->{'MECH'};

  $PHJS->get_local($Args{'file'}) or FB3::Convert::Error($X, "Can't open file for phantomjs : ".$Args{'file'});
  $X->{'ContentBefore'} = $PHJS->content( format => 'html' );

#если нет проблем со стилями - убрать блок
#  my $CssDebug =  $PHJS->eval_in_page(<<'LoadCSS', 'Foobar/1.0');
#(function(arguments){
#  var LinkList = document.getElementsByTagName('link');
#  var LinkList = Array.prototype.slice.call(LinkList);
#  if (LinkList.length > 0) {
#    LinkList.forEach(function(link) {
#      link.href = link.href; //конвертация в file://path в тексте html
#    });
#  }
#})(arguments);
#LoadCSS
  #return $CssDebug;

  my $Debug =  $PHJS->eval_in_page(<<'JS', "Foobar/1.0", $X->{'LocalLinks'});
(function(arguments){
  // Node types
  var ELEMENT_NODE = 1;
  var TEXT_NODE = 3;

  var LocalLinks = arguments[1] || {};
  var FILENAME = window.location.pathname;
  var RET = Array();

  //настройки
  var TooMuchFontSize = 4; //На сколько px нужно быть увеличенным шрифтом от document.body, чтобы тебя посчитали "большим" 
  var TooMuchMargin = 6; //На сколько px нужно иметь отступ, чтобы тебя посчитали "отбитым текстом" 
  var TooMuchBR = 1; //Сумма <br>, считаемая отбивкой 


  var BlockLevel = {
    'address':1,
    'article':1,
    'aside':1,
    'blockquote':1,
    'canvas':1,
    'dd':1,
    'div':1,
    'dl':1,
    'dt':1,
    'fieldset':1,
    'figcaption':1,
    'figure':1,
    'footer':1,
    'form':1,
    'header':1,
    //'hr', //бесполезно
    'main':1,
    'nav':1,
    'noscript':1,
    'ol':1,
    'ul':1,
    'li':1,
    'output':1,
    'p':1,
    'pre':1,
    'section':1,
    'table':1,
    'tfoot':1,
    //'video', //слишком
    //↓↓↓ формально не блок-левел ↓↓↓
    'th':1,
    'tr':1,
    'td':1
  };

  String.prototype.HaveIn = function(words) {
    var str = this;
    str = str.trim();
    str = str.replace(/[\s\n\r]+/g,' ');
    var sp = str.split(' ');
    var H = {}; words.forEach(function(v){H[v]=1;});
    var find = 0;
    ret = sp.forEach( function(v){ if (v in H) {find=1;return;}} );
    return find;
  };

  String.prototype.digCut = function() { //откусывает буквы, оставляя число
    return parseInt(this.replace(new RegExp('/[^\d]+/', 'g'), ''));
  };

  Array.prototype.digMax = function() { //возвращает максимальное число в массиве
    var Max = 0;
    this.forEach(function(v){if(parseInt(v)>Max) Max = parseInt(v);});
    return Max;
  };

  Element.prototype.setTagName=function(strTN) {
    if (this.tagName.toUpperCase() == strTN.toUpperCase()) return;
    var newNode = document.createElement(strTN);
    newNode.innerHTML = this.innerHTML;
    for (var i = 0, atts = this.attributes, n = atts.length; i < n; i++){
      newNode.setAttribute(atts[i].nodeName, atts[i].nodeValue);
    }
    this.parentElement.replaceChild(newNode,this);
  }

  var FirstTextLength = 0;
  FindCandidateNode = 0;
  var Balls = 3; //по умолчанию баллы за то, что кандидат вверху (может быть сброшен в контексте анализа)

  //бежим по нодам в body
  nodes = Array.prototype.slice.call(document.body.childNodes);
  var BreakException = {};
  try {  
    nodes.forEach( 
      function(currNode, currIndex) {
        var NodeName = currNode.nodeName.toLowerCase();
        var Changed = 0;
        
        if (currNode.nodeType == TEXT_NODE) { //Текстовая нода
          if (!FindCandidateNode) FirstTextLength += currNode.nodeValue.trim().length;
          if (FirstTextLength > 3) Balls = 0; //в начале какой-то значимый "голый текст", +3 в баллы не светит (<=3 символа будем считать мусором)
          RET.push('[INDEX: ' + currIndex + ']' + currNode.nodeValue.trim() + "[FirstTextLength:"+ FirstTextLength +"]"); 
        } else { // Видимо element-нода
          Calc = ParseCandidate(currNode);
          var Cand = Calc['CALC'];
          if (!FindCandidateNode && Cand['TextLength'] >= 0 && Cand['TextLength'] <= 3) {
            FirstTextLength += Cand['TextLength']; //какой-то малозначимый текст в блоке, будем считать, что это мусор в начале
          } else if (Cand['TextLength'] > 3) {

            if (currNode.id) {
              var ID = currNode.id;
              if (ID != null && LocalLinks[FILENAME] != null && ID in LocalLinks[FILENAME]) {
                Calc['BALLS'] += 3; // на ноду ссылаются из любого файла в книге
              }
            }

            //наткнулись на ноду с текстом, хватит перебирать "голый текст" в начале
            FindCandidateNode++; // (!!!) подумать, тут ему место или внизу ветки, смотря что мы считаем за кандидата

            if (
              !(NodeName in BlockLevel) || // (!!!) подумать - нужно оно, или мы все элемент-ноды считаем
              NodeName.match(/^h\d+$/) // <h*> надо пропустить
            ) return;

            //смотрим, что насчитали по текущему блоку
            Calc['BALLS'] += Balls; //Сложим баллы по ноде
            Balls = 0; //следующему кандидату баллы за начало страницы уже не достанутся

            if (Calc['BALLS'] >= 10) { // По всей видимости детектировали заголовок
              currNode.setTagName("h6");
              Changed = 1;
            }

          }
          RET.push( 
            {
              "DEBUG": '[INDEX:' + currIndex + ']' + currNode.outerHTML + '[DUMP:' + JSON.stringify(Calc) + ']',
              "BALLS": Calc['BALLS'],
              "CHANGED": Changed
            }
          ); 
          if (FindCandidateNode>=2) throw BreakException; //хватит перебирать
        }
      }
    );
  } catch (e) {
    if (e !== BreakException) throw e;
  }

  return RET;

  function ParseCandidate(candidate) {
    Calc = CalcNodeRecursive(candidate); //калькуляция текущей ноды
    TopNext = TopNextNodes(candidate); //калькуляция ближайших нод снизу, влияющих на отступ

    //подсчет баллов для установления вероятности заголовка
    var Cballs = 0;
    if (Calc['TextLength'] > 0 && Calc['TextLength'] < 100) Cballs += 3;
    if (Calc['MagicWords'] > 0) Cballs += 7;
    if (Calc['HaveCenter'] > 0) Cballs += 3;

    //увеличенный шрифт?
    var BodyStyle = simpleStyles(document.body);
    if ('font-size' in BodyStyle) { //вообще так не бывает
      var MainFsize = BodyStyle['font-size'].digCut();
      if (Calc['TextSize'].digMax() - MainFsize >= TooMuchFontSize) Cballs += 3;
    }

    //отбивка?
    var BRSumm=0;
    var MarginSumm = 0;
 
    if (Calc['HaveBRbottom'] > 0) {
      BRSumm += Calc['HaveBRbottom']; //нашли отбивку br по низу
    }
     
    //стили отбивки по низу
    //по умолчанию в блоках маргин по величине шрифта - это норма и выставляется в DOM автоматически, если не указаны стили
    // в <span> и пр - Top|Bottom - всегда нули, не зависимо от style='margin|padding'
    if ( Calc['Bottom'].digMax() > Calc['TextSize'].digMax() ) {
      MarginSumm += (Calc['Bottom'].digMax() - Calc['TextSize'].digMax());
    }

    //смотрим соседей снизу
    TopNext['DATA'].forEach(
      function(v) {
        if ( v['HaveBRtop'] > 0 ) BRSumm += v['HaveBRtop']; //нашли отбивку br соседа по верху
        if ( v['Top'].digMax() > v['TextSize'].digMax() ) { //стили отбивки нижнего соседа по верху 
          MarginSumm += (v['Top'].digMax() - v['TextSize'].digMax());
        }
      }
    );

    if (BRSumm >= TooMuchBR || MarginSumm >= TooMuchMargin) Cballs += 3; //нашли достаточную отбивку

    return {
      'CALC': Calc,
      'NEXT': TopNext,
      'BALLS': Cballs
    };
  }

  function CalcNodeRecursive(node) {
    var DBG;
    var nodes = Array.prototype.slice.call(node.childNodes,0);
    if (!nodes.length) nodes = [node];
    //DBG = nodes.length;

    var TL = 0; //длина текста
    var MW = 0; //наличие волшебных слов
    var TS = Array(); //размеры текста в ноде
    var MB = Array(); //отступы снизу margin|padding в ноде
    var MT = Array(); //отступы вверху margin|padding в ноде
    var BRB = 0; //имеет <br/> в отбивку снизу
    var BRT = 0; //имеет <br/> в отбивку сверху
    var CNT = 0; //имеет текст, выровненный по цетру относительно родительского блок-левел элемента

    nodes.forEach(
      function(currNode, currIndex) {
        if (!currNode) return;
        if (currNode.nodeType == TEXT_NODE) {
          val = currNode.nodeValue;
          TL += val.trim().length;

          if ( val.toLowerCase().HaveIn(Array('глава','часть','chapter','part')) ) {
            MW += 1;
          }

          var styles = simpleStyles(currNode.parentNode);
          var block;
          var PN = currNode.parentNode.nodeName.toLowerCase();
          if (PN in BlockLevel) block = 1; //для остальных нет эффекта отступов

          if (block && 'text-align' in styles && styles['text-align'].toLowerCase() == 'center') CNT = 1;

          if (styles['font-size']) TS.push(styles['font-size'].digCut());
          
          var bl = 0;
          if (styles['margin-bottom'] && block) bl += styles['margin-bottom'].digCut(); 
          if (styles['padding-bottom'] && block) bl += styles['padding-bottom'].digCut(); 
          MB.push(bl);

          var tl = 0;
          if (styles['margin-top'] && block) tl += styles['margin-top'].digCut();
          if (styles['padding-top'] && block) tl += styles['padding-top'].digCut(); 
          MT.push(tl);

          if (val.trim().length > 0) BRB = 0; //это уже не отбивка <br> снизу, а межстрочный (голый текст за br)

        } else if (currNode.nodeType == ELEMENT_NODE) {

          var r = {};
          if (currNode.childNodes
           && currNode.innerHTML.trim() != '' // почему-то <tag></tag> повергает в бесконечную рекурсию, будто у него есть чайлдноды
          ) {
            r = CalcNodeRecursive(currNode);
          }

          if (currNode.nodeName.toLowerCase() == 'br') {
            BRB++;
            if (!( TL > 0 || ("TextLength" in r && r['TextLength']==0) )) BRT++; //br вверху, перед ним нет голого текста или ноды с текстом
          } else if ("TextLength" in r && r['TextLength'] > 0) {
            BRB = 0; //и это тоже не отбивка снизу (нода за br, имеющая текст)
          }

          if ("HaveCenter" in r) MW += r['HaveCenter'];
          if ("MagicWords" in r) MW += r['MagicWords'];

          // push - избыточно, но полезно для отладки
          if ("TextLength" in r) {
            TL += r['TextLength'];
            for (var i=0;i<r['TextSize'].length;i++) {
              TS.push(r['TextSize'][i]);
            }
          }

          if ("Bottom" in r) {
            for (var i=0;i<r['Bottom'].length;i++) {
              MB.push(r['Bottom'][i]);
            }
          }

          if ("Top" in r) {
            for (var i=0;i<r['Top'].length;i++) {
              MT.push(r['Top'][i]);
            }
          }

        }
      }
    );

    return {
      'TextLength': TL,
      'MagicWords': MW,
      'TextSize': TS,
      'Bottom': MB,
      'Top': MT,
      'HaveBRbottom': BRB,
      'HaveBRtop': BRT,
      'HaveCenter': CNT,
      'DEBUG': DBG
    }
  }

  function TopNextNodes(node) {
    var el = node.nextSibling;
    var DATA = Array();
    var i = 1;

    while (el) {
      var Calculate = CalcNodeRecursive(el);
      DATA.push(Calculate);
      if (Calculate['TextLength'] > 0 ) break; //встретили текст, хватит месить
      el = el.nextSibling;
      i++;
    }

    return {'DATA': DATA};
  }

  function simpleStyles(node) {
    var style = window.getComputedStyle(node);
    var styleMap = {};
    for (var i = 0; i < style.length; i++) {
      var prop = style[i];
      var value = style.getPropertyValue(prop);
      styleMap[prop] = value;
    }
    return styleMap;
  }

})(arguments);
JS

  my $Changed = 0;
  foreach (@$Debug) {
    $Changed = 1 if ref $_ eq 'HASH' && $_->{'CHANGED'}; 
  }

  my $CONTENT = $PHJS->content( format => 'html' );

  #Дебаг измененных эвристикой файлов 
  if ($X->{'DebugPath'}
   ##&& $Changed #всех или измененные
  ) {
    my $SrcFile = $X->{'SrcFile'}; 
    my $FND = $SrcFile;
    $FND =~ s/.*?([^\/]+)$/$1/g;
    $FND = ($X->{'DebugPrefix'} ? "[".$X->{'DebugPrefix'}."]_" : "").$FND;

    #исходник
    File::Copy::copy($SrcFile, $X->{'DebugPath'}.'/'.$FND.'.src') or die "Can't copy file $SrcFile : $!";

    #после прочитки в DOM
    open my $Fb,">:utf8",$X->{'DebugPath'}.'/'.$FND.".before";
    print $Fb $X->{'ContentBefore'};
    close $Fb;

    #после изменения + debug
    open my $Fc,">:utf8",$X->{'DebugPath'}.'/'.$FND.".debug";
    print $Fc "DEBUG\n";
    print $Fc Data::Dumper::Dumper($Debug);
    print $Fc "\n============\n";
    print $Fc "RESULT\n";
    print $Fc $CONTENT;
    close $Fc;

  }
  #//Дебаг измененных эвристикой файлов 

  return {
    'CONTENT' => $CONTENT,
    'DBG' => $Debug,
    'CHANGED' => $Changed,
  }

}

1;