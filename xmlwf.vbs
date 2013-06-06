Set args = WScript.Arguments
if args.Count<=1 then
  WScript.Echo "Usage: xmlwf <schema> <file> ..."
  WScript.Quit 0
end if
Set WshShell = WScript.CreateObject("WScript.Shell")
Set doc = WScript.CreateObject("MSXML2.DOMDocument.4.0")
Set cache = WScript.CreateObject("MSXML2.XMLSchemaCache.4.0")
doc.async=false
doc.validateOnParse=true
cache.add "http://www.fictionbook.org/FictionBook3/body",args(0)
doc.schemas=cache
errors=0
for i=1 to args.Count-1
  if not doc.load(args(i)) then
    errors=1
    WScript.Echo "Error at",args(i)+", line",cstr(doc.parseError.line)+", column",cstr(doc.parseError.linepos)+":", doc.parseError.reason
  end if
next
if errors=0 then WScript.Echo "No errors found"
