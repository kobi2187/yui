import tables, options, strutils, os, sequtils, sets, sugar
import strformat

# Import YUI parser from validator module
import yui_validator

# Just for clarity - we're using these types from the validator
type
  YuiApp = yui_validator.YuiApp
  Element = yui_validator.Element
  BaseProperties = yui_validator.BaseProperties
  EventHandler = yui_validator.EventHandler
  Binding = yui_validator.Binding
  StateVar = yui_validator.StateVar
  BindDirection = yui_validator.BindDirection
  LayoutAlign = yui_validator.LayoutAlign
  LayoutJustify = yui_validator.LayoutJustify

# Simple context for tracking what we need
type CodeContext = object
  stateUpdates: seq[string]   # Code to update UI from state
  widgetCounter: int

var ctx: CodeContext

# Figure out Nim type from YAML
proc nimTypeFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    if node.content == "true" or node.content == "false": return "bool"
    elif node.content.len > 0 and node.content.allCharsInSet(Digits + {'.', '-'}):
      if '.' in node.content: return "float" else: return "int"
    else: return "string"
  of ySequence: return "seq[string]"
  of yMapping: return "Table[string, string]"
  else: return "string"

# Convert YAML to Nim literal
proc nimValueFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    let nimType = nimTypeFromYamlNode(node)
    case nimType
    of "string": return "\"" & node.content & "\""
    of "bool", "int", "float": return node.content
    else: return "\"" & node.content & "\""
  of ySequence:
    if node.elems.len == 0: return "@[]"
    var values: seq[string] = @[]
    for elem in node.elems:
      values.add(nimValueFromYamlNode(elem))
    return "@[" & values.join(", ") & "]"
  of yMapping: return "initTable[string, string]()"
  else: return "\"\""

# Extract state vars from strings
proc extractStateVars(content: string): seq[string] =
  result = @[]
  var i = 0
  while i < content.len:
    if content[i] == '{':
      var j = i + 1
      var varName = ""
      while j < content.len and content[j] != '}':
        varName.add(content[j])
        j += 1
      if j < content.len and varName.len > 0:
        result.add(varName.strip())
        i = j
    i += 1

# Convert "Count: {counter}" to OwlKettle string interpolation
proc makeOwlKettleInterpolation(content: string): string =
  var result = content
  let vars = extractStateVars(content)
  for v in vars:
    result = result.replace("{" & v & "}", "\" & $state." & v & " & \"")
  return "\"" & result & "\""

# Generate unique widget names when needed
proc nextWidgetName(elementType: string): string =
  result = elementType & $ctx.widgetCounter
  inc ctx.widgetCounter

# Main tree walker for OwlKettle
proc visitElement(element: Element, indent: int): string =
  let indentStr = "  ".repeat(indent)
  
  case element.elementType:
  
  of "label":
    result = indentStr & "Label:\n"
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        # Dynamic content
        let interpolated = makeOwlKettleInterpolation(content)
        result &= indentStr & "  text: " & interpolated & "\n"
      else:
        result &= indentStr & "  text: \"" & content & "\"\n"
    else:
      result &= indentStr & "  text: \"Label\"\n"
  
  of "button":
    result = indentStr & "Button:\n"
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        let interpolated = makeOwlKettleInterpolation(content)
        result &= indentStr & "  text: " & interpolated & "\n"
      else:
        result &= indentStr & "  text: \"" & content & "\"\n"
    else:
      result &= indentStr & "  text: \"Button\"\n"
    
    # Handle click events
    if element.events.hasKey("on_click"):
      let handler = element.events["on_click"].handler.split('/')[0]
      result &= indentStr & "  proc clicked() =\n"
      result &= indentStr & "    " & handler & "()\n"
  
  of "input":
    result = indentStr & "Entry:\n"
    
    # Handle binding
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  text: state." & bindProp & "\n"
      result &= indentStr & "  proc changed(newText: string) =\n"
      result &= indentStr & "    state." & bindProp & " = newText\n"
      result &= indentStr & "    app.redraw()\n"
    
    # Handle placeholder
    if element.rawProperties.hasKey("placeholder"):
      result &= indentStr & "  placeholder: \"" & element.rawProperties["placeholder"].content & "\"\n"
  
  of "checkbox":
    result = indentStr & "CheckButton:\n"
    if element.content.isSome:
      result &= indentStr & "  text: \"" & element.content.get & "\"\n"
    else:
      result &= indentStr & "  text: \"Checkbox\"\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  state: state." & bindProp & "\n"
      result &= indentStr & "  proc toggled(newState: bool) =\n"
      result &= indentStr & "    state." & bindProp & " = newState\n"
      result &= indentStr & "    app.redraw()\n"
  
  of "select":
    result = indentStr & "ComboBoxText:\n"
    
    # Add options - OwlKettle needs them added programmatically
    if element.rawProperties.hasKey("options") and element.rawProperties["options"].kind == ySequence:
      result &= indentStr & "  # Options would be added in setup\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  proc changed() =\n"
      result &= indentStr & "    # Handle selection change\n"
      result &= indentStr & "    app.redraw()\n"
  
  of "textarea":
    result = indentStr & "TextView:\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  text: state." & bindProp & "\n"
      result &= indentStr & "  proc changed(newText: string) =\n"
      result &= indentStr & "    state." & bindProp & " = newText\n"
      result &= indentStr & "    app.redraw()\n"
  
  of "slider":
    var minVal = "0.0"
    var maxVal = "100.0"
    if element.rawProperties.hasKey("min"): minVal = element.rawProperties["min"].content & ".0"
    if element.rawProperties.hasKey("max"): maxVal = element.rawProperties["max"].content & ".0"
    
    result = indentStr & "Scale:\n"
    result &= indentStr & "  min: " & minVal & "\n"
    result &= indentStr & "  max: " & maxVal & "\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: state." & bindProp & ".float\n"
      result &= indentStr & "  proc valueChanged(newValue: float) =\n"
      result &= indentStr & "    state." & bindProp & " = newValue.int\n"
      result &= indentStr & "    app.redraw()\n"
  
  of "progress":
    result = indentStr & "ProgressBar:\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: state." & bindProp & ".float / 100.0\n"
    elif element.rawProperties.hasKey("value"):
      let value = element.rawProperties["value"].content
      if value.startsWith("{") and value.endsWith("}"):
        let stateVar = value[1..^2].strip()
        result &= indentStr & "  value: state." & stateVar & ".float / 100.0\n"
  
  # Container widgets
  of "row":
    result = indentStr & "Box:\n"
    result &= indentStr & "  orient: OrientHorizontal\n"
    
    if element.properties.spacing.isSome:
      result &= indentStr & "  spacing: " & element.properties.spacing.get & "\n"
    
    # Handle alignment
    if element.properties.align.isSome:
      case element.properties.align.get:
      of AlignCenter: result &= indentStr & "  valign: AlignCenter\n"
      of AlignEnd: result &= indentStr & "  valign: AlignEnd\n"
      of AlignStart: result &= indentStr & "  valign: AlignStart\n"
      of AlignStretch: result &= indentStr & "  valign: AlignFill\n"
    
    # Visit children
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, indent + 1)
  
  of "column":
    result = indentStr & "Box:\n"
    result &= indentStr & "  orient: OrientVertical\n"
    
    if element.properties.spacing.isSome:
      result &= indentStr & "  spacing: " & element.properties.spacing.get & "\n"
    
    # Handle alignment
    if element.properties.align.isSome:
      case element.properties.align.get:
      of AlignCenter: result &= indentStr & "  halign: AlignCenter\n"
      of AlignEnd: result &= indentStr & "  halign: AlignEnd\n"
      of AlignStart: result &= indentStr & "  halign: AlignStart\n"
      of AlignStretch: result &= indentStr & "  halign: AlignFill\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, indent + 1)
  
  of "group":
    result = indentStr & "Frame:\n"
    if element.content.isSome:
      result &= indentStr & "  label: \"" & element.content.get & "\"\n"
    else:
      result &= indentStr & "  label: \"Group\"\n"
    
    # OwlKettle frames contain a child widget
    if element.children.isSome and element.children.get.len > 0:
      if element.children.get.len == 1:
        result &= visitElement(element.children.get[0], indent + 1)
      else:
        # Multiple children - wrap in a box
        result &= indentStr & "  Box:\n"
        result &= indentStr & "    orient: OrientVertical\n"
        for child in element.children.get:
          result &= visitElement(child, indent + 2)
  
  of "tab":
    result = indentStr & "Notebook:\n"
    
    if element.children.isSome:
      for child in element.children.get:
        if child.elementType == "tab":
          result &= indentStr & "  NotebookPage:\n"
          let tabTitle = if child.content.isSome: child.content.get else: "Tab"
          result &= indentStr & "    text: \"" & tabTitle & "\"\n"
          
          if child.children.isSome:
            if child.children.get.len == 1:
              result &= visitElement(child.children.get[0], indent + 2)
            else:
              result &= indentStr & "    Box:\n"
              result &= indentStr & "      orient: OrientVertical\n"
              for tabChild in child.children.get:
                result &= visitElement(tabChild, indent + 3)
  
  of "grid":
    # OwlKettle has Grid widget
    result = indentStr & "Grid:\n"
    
    if element.properties.spacing.isSome:
      result &= indentStr & "  columnSpacing: " & element.properties.spacing.get & "\n"
      result &= indentStr & "  rowSpacing: " & element.properties.spacing.get & "\n"
    
    # Parse grid dimensions
    var cols = 2
    if element.dimensions.isSome:
      let parts = element.dimensions.get.split('x')
      if parts.len > 0:
        try: cols = parseInt(parts[0])
        except: discard
    
    # Add children with grid positions
    if element.children.isSome:
      var cellIndex = 0
      for child in element.children.get:
        let row = cellIndex div cols
        let col = cellIndex mod cols
        
        # OwlKettle Grid children need position info
        result &= indentStr & "  GridChild:\n"
        result &= indentStr & "    left: " & $col & "\n"
        result &= indentStr & "    top: " & $row & "\n"
        result &= visitElement(child, indent + 2)
        
        inc cellIndex
  
  else:
    # Fallback for unsupported elements
    result = indentStr & "Label:\n"
    result &= indentStr & "  text: \"[" & element.elementType & "]\"\n"

# Main OwlKettle app generator
proc generateOwlKettleApp*(app: YuiApp): string =
  ctx = CodeContext()  # Reset context
  
  var code = """
import owlkettle
import tables

# Generated from YAML-UI: """ & app.app & """

# Application state
type AppState = object
"""
  
  # Generate state variables
  if app.state.isSome:
    for name, stateVar in app.state.get.pairs:
      let nimType = nimTypeFromYamlNode(stateVar.value)
      code &= "  " & name & ": " & nimType & "\n"
  else:
    code &= "  dummy: int  # No state defined\n"
  
  # Initialize state
  code &= "\n# Initialize state\n"
  code &= "var state = AppState(\n"
  if app.state.isSome:
    var stateInits: seq[string] = @[]
    for name, stateVar in app.state.get.pairs:
      let nimValue = nimValueFromYamlNode(stateVar.value)
      stateInits.add("  " & name & ": " & nimValue)
    code &= stateInits.join(",\n") & "\n"
  code &= ")\n\n"
  
  # Generate action handlers
  if app.actions.isSome:
    code &= "# Action handlers\n"
    for actionDef in app.actions.get:
      let parts = actionDef.split('/')
      let actionName = parts[0]
      var arity = 0
      if parts.len > 1:
        try: arity = parseInt(parts[1])
        except: discard
      
      code &= "proc " & actionName & "("
      if arity > 0: code &= "value: auto"
      code &= ") =\n"
      
      # Common patterns
      case actionName:
      of "increment":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "  inc state.counter\n"
        else: code &= "  echo \"increment called\"\n"
      of "decrement":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "  if state.counter > 0: dec state.counter\n"
        else: code &= "  echo \"decrement called\"\n"
      of "reset":
        if app.state.isSome:
          for name, stateVar in app.state.get.pairs:
            let defaultValue = nimValueFromYamlNode(stateVar.value)
            code &= "  state." & name & " = " & defaultValue & "\n"
        else: code &= "  echo \"reset called\"\n"
      else:
        code &= "  echo \"" & actionName & " called\"\n"
      
      code &= "  app.redraw()\n\n"
  
  # Main view function
  code &= "# Main view\n"
  code &= "proc createView(): Widget =\n"
  code &= "  result = gui:\n"
  code &= "    Window:\n"
  code &= "      title: \"" & app.app & "\"\n"
  code &= "      defaultSize: (800, 600)\n"
  
  # Generate UI tree
  if app.view.len > 0:
    if app.view.len == 1:
      code &= visitElement(app.view[0], 3)
    else:
      # Multiple root elements - wrap in a box
      code &= "      Box:\n"
      code &= "        orient: OrientVertical\n"
      for element in app.view:
        code &= visitElement(element, 4)
  else:
    code &= "      Label:\n"
    code &= "        text: \"No UI elements defined\"\n"
  
  # Main function
  code &= """
# Main application
proc main() =
  let app = newApplication("generated.yui.app")
  
  proc activate(app: Application) =
    let window = createView()
    window.show()
    app.addWindow(window)
  
  app.connect("activate", activate)
  
  let exitCode = app.run()
  quit(exitCode)

when isMainModule:
  main()
"""
  
  return code

# Function to parse YUI from file and generate OwlKettle code
proc generateOwlKettleFromYuiFile*(filepath: string): string =
  let app = yui_validator.loadAndValidateYuiFile(filepath).app
  return generateOwlKettleApp(app)

# Validate the generated OwlKettle app and report any issues
proc validateOwlKettleOutput*(code: string): seq[string] =
  var issues: seq[string] = @[]
  if not code.contains("import owlkettle"): issues.add("Missing owlkettle import")
  if not code.contains("proc main()"): issues.add("Missing main procedure")
  if not code.contains("newApplication"): issues.add("Missing application creation")
  return issues

# Main function for CLI usage
when isMainModule:
  if paramCount() < 1:
    echo "Usage: yui_owlkettle_generator <file.yui> [output.nim]"
    echo "Options:"
    echo "  --validate   Validate the YUI file before generating code"
    quit(1)
  
  let inputFile = paramStr(1)
  echo "Generating OwlKettle code from ", inputFile
  
  let validate = paramCount() >= 2 and paramStr(2) == "--validate"
  
  if validate:
    let validation = yui_validator.loadAndValidateYuiFile(inputFile)
    if validation.errors.len > 0:
      echo "YUI validation errors:"
      for error in validation.errors:
        echo "  - ", error
      quit(1)
  
  let owlkettleCode = generateOwlKettleFromYuiFile(inputFile)
  
  let issues = validateOwlKettleOutput(owlkettleCode)
  if issues.len > 0:
    echo "Warning: Potential issues in generated code:"
    for issue in issues:
      echo "  - ", issue
  
  let outputFile = if validate and paramCount() >= 3: paramStr(3) 
                   elif not validate and paramCount() >= 2: paramStr(2)
                   else: ""
  
  if outputFile != "":
    writeFile(outputFile, owlkettleCode)
    echo "OwlKettle code written to ", outputFile
    echo "Compile with: nim c -r ", outputFile
  else:
    echo owlkettleCode