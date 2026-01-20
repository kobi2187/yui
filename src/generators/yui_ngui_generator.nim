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

# Code generation context - just what we need, nothing fancy
type CodeContext = object
  refreshStatements: seq[string]  # Statements that update widgets from state
  widgetCounter: int              # For generating unique widget names

var ctx: CodeContext

# Helper function to determine the Nim type from a YAML node
proc nimTypeFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    if node.content == "true" or node.content == "false": return "bool"
    elif node.content.len > 0 and node.content.allCharsInSet(Digits + {'.', '-'}):
      if '.' in node.content: return "float" else: return "int"
    else: return "string"
  of ySequence: return "seq[string]"
  of yMapping: return "Table[string, string]"
  else: return "auto"

# Helper function to format YAML node as Nim literal
proc nimValueFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    let nimType = nimTypeFromYamlNode(node)
    case nimType
    of "string": return &"\"{node.content}\""
    of "bool", "int", "float": return node.content
    else: return &"\"{node.content}\""
  of ySequence:
    if node.elems.len == 0: return "@[]"
    var values: seq[string] = @[]
    for elem in node.elems:
      values.add(nimValueFromYamlNode(elem))
    return "@[" & values.join(", ") & "]"
  of yMapping: return "initTable[string, string]()"
  else: return "\"\""

# Extract state variable references from strings like "Count: {counter}"
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

# Convert "Count: {counter}" to proper Nim string interpolation
proc makeInterpolation(content: string): string =
  var result = content
  let vars = extractStateVars(content)
  for v in vars:
    result = result.replace("{" & v & "}", "\" & $appState." & v & " & \"")
  return "\"" & result & "\""

# Generate a unique widget name
proc nextWidgetName(elementType: string): string =
  result = elementType & $ctx.widgetCounter
  inc ctx.widgetCounter

# The main tree walker - each element type knows how to generate itself
proc visitElement(element: Element, parent: string, indent: int): string =
  let indentStr = "  ".repeat(indent)
  let widgetName = if element.properties.id.isSome: element.properties.id.get else: nextWidgetName(element.elementType)
  
  case element.elementType:
  
  of "label":
    result = indentStr & "let " & widgetName & " = newLabel("
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        # Dynamic content - needs refresh
        let interpolated = makeInterpolation(content)
        result &= interpolated & ")\n"
        ctx.refreshStatements.add("  " & widgetName & ".text = " & interpolated)
      else:
        result &= "\"" & content & "\")\n"
    else:
      result &= "\"Label\")\n"
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "button":
    result = indentStr & "let " & widgetName & " = newButton("
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        let interpolated = makeInterpolation(content)
        result &= interpolated & ")\n"
        ctx.refreshStatements.add("  " & widgetName & ".text = " & interpolated)
      else:
        result &= "\"" & content & "\")\n"
    else:
      result &= "\"Button\")\n"
    
    # Wire up click handler if present
    if element.events.hasKey("on_click"):
      let handler = element.events["on_click"].handler.split('/')[0]
      result &= indentStr & widgetName & ".onClicked = proc() = " & handler & "()\n"
    
    # Handle visibility conditions
    if element.properties.visible.isSome:
      let visExpr = element.properties.visible.get
      if visExpr.startsWith("{") and visExpr.endsWith("}"):
        let condition = visExpr[1..^2].strip().replace("!", "not ")
        ctx.refreshStatements.add("  " & widgetName & ".enabled = " & condition)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "input":
    result = indentStr & "let " & widgetName & " = newEntry()\n"
    
    # Handle binding
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".text = $appState." & bindProp & "\n"
      result &= indentStr & widgetName & ".onChanged = proc() =\n"
      result &= indentStr & "  appState." & bindProp & " = " & widgetName & ".text\n"
      result &= indentStr & "  refreshUI()\n"
      ctx.refreshStatements.add("  " & widgetName & ".text = $appState." & bindProp)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "checkbox":
    result = indentStr & "let " & widgetName & " = newCheckbox("
    if element.content.isSome:
      result &= "\"" & element.content.get & "\")\n"
    else:
      result &= "\"Checkbox\")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".checked = appState." & bindProp & "\n"
      result &= indentStr & widgetName & ".onToggled = proc() =\n"
      result &= indentStr & "  appState." & bindProp & " = " & widgetName & ".checked\n"
      result &= indentStr & "  refreshUI()\n"
      ctx.refreshStatements.add("  " & widgetName & ".checked = appState." & bindProp)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "select":
    result = indentStr & "let " & widgetName & " = newCombobox()\n"
    
    # Add options
    if element.rawProperties.hasKey("options") and element.rawProperties["options"].kind == ySequence:
      for optionNode in element.rawProperties["options"]:
        var labelText = ""
        if optionNode.kind == yMapping:
          for pair in optionNode.pairs:
            if pair[0].content == "label":
              labelText = pair[1].content
              break
        elif optionNode.kind == yScalar:
          labelText = optionNode.content
        
        if labelText != "":
          result &= indentStr & widgetName & ".add(\"" & labelText & "\")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".onSelected = proc() =\n"
      result &= indentStr & "  if " & widgetName & ".selected >= 0:\n"
      result &= indentStr & "    appState." & bindProp & " = " & widgetName & ".text\n"
      result &= indentStr & "    refreshUI()\n"
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "textarea":
    result = indentStr & "let " & widgetName & " = newMultilineEntry()\n"
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".text = $appState." & bindProp & "\n"
      result &= indentStr & widgetName & ".onChanged = proc() =\n"
      result &= indentStr & "  appState." & bindProp & " = " & widgetName & ".text\n"
      result &= indentStr & "  refreshUI()\n"
      ctx.refreshStatements.add("  " & widgetName & ".text = $appState." & bindProp)
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "slider":
    var minVal = "0"
    var maxVal = "100"
    if element.rawProperties.hasKey("min"): minVal = element.rawProperties["min"].content
    if element.rawProperties.hasKey("max"): maxVal = element.rawProperties["max"].content
    
    result = indentStr & "let " & widgetName & " = newSlider(" & minVal & ", " & maxVal & ")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".value = appState." & bindProp & "\n"
      result &= indentStr & widgetName & ".onChanged = proc() =\n"
      result &= indentStr & "  appState." & bindProp & " = " & widgetName & ".value\n"
      result &= indentStr & "  refreshUI()\n"
      ctx.refreshStatements.add("  " & widgetName & ".value = appState." & bindProp)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "progress":
    result = indentStr & "let " & widgetName & " = newProgressBar()\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".value = appState." & bindProp & "\n"
      ctx.refreshStatements.add("  " & widgetName & ".value = appState." & bindProp)
    elif element.rawProperties.hasKey("value"):
      let value = element.rawProperties["value"].content
      if value.startsWith("{") and value.endsWith("}"):
        let stateVar = value[1..^2].strip()
        result &= indentStr & widgetName & ".value = appState." & stateVar & "\n"
        ctx.refreshStatements.add("  " & widgetName & ".value = appState." & stateVar)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  # Container elements - these just create a container and visit their children
  of "row":
    result = indentStr & "let " & widgetName & " = newHorizontalBox()\n"
    if element.properties.spacing.isSome:
      result &= indentStr & widgetName & ".padded = true\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName, indent + 1)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "column":
    result = indentStr & "let " & widgetName & " = newVerticalBox()\n"
    if element.properties.spacing.isSome:
      result &= indentStr & widgetName & ".padded = true\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName, indent + 1)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "group":
    result = indentStr & "let " & widgetName & " = newGroup("
    if element.content.isSome:
      result &= "\"" & element.content.get & "\")\n"
    else:
      result &= "\"Group\")\n"
    
    let boxName = widgetName & "_box"
    result &= indentStr & "let " & boxName & " = newVerticalBox()\n"
    result &= indentStr & boxName & ".padded = true\n"
    result &= indentStr & widgetName & ".child = " & boxName & "\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, boxName, indent + 1)
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "tab":
    result = indentStr & "let " & widgetName & " = newTab()\n"
    
    if element.children.isSome:
      for i, child in element.children.get:
        if child.elementType == "tab":
          let pageId = widgetName & "_page" & $i
          result &= indentStr & "let " & pageId & " = newVerticalBox()\n"
          result &= indentStr & pageId & ".padded = true\n"
          
          if child.children.isSome:
            for tabChild in child.children.get:
              result &= visitElement(tabChild, pageId, indent + 1)
          
          let tabTitle = if child.content.isSome: child.content.get else: "Tab " & $(i+1)
          result &= indentStr & widgetName & ".add(\"" & tabTitle & "\", " & pageId & ")\n"
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  of "grid":
    # Grid is just nested boxes - works fine
    result = indentStr & "let " & widgetName & " = newVerticalBox()\n"
    result &= indentStr & widgetName & ".padded = true\n"
    
    var cols = 2
    if element.dimensions.isSome:
      let parts = element.dimensions.get.split('x')
      if parts.len > 0:
        try: cols = parseInt(parts[0])
        except: discard
    
    if element.children.isSome:
      var childIndex = 0
      var rowIndex = 0
      
      while childIndex < element.children.get.len:
        let rowId = widgetName & "_row" & $rowIndex
        result &= indentStr & "let " & rowId & " = newHorizontalBox()\n"
        result &= indentStr & rowId & ".padded = true\n"
        
        for col in 0..<cols:
          if childIndex < element.children.get.len:
            result &= visitElement(element.children.get[childIndex], rowId, indent + 1)
            inc childIndex
          else:
            result &= indentStr & "  " & rowId & ".add(newLabel(\"\"))\n"
        
        result &= indentStr & widgetName & ".add(" & rowId & ")\n"
        inc rowIndex
    
    result &= indentStr & parent & ".add(" & widgetName & ")\n"
  
  else:
    # Fallback for unsupported elements
    result = indentStr & "let " & widgetName & " = newLabel(\"[" & element.elementType & "]\")\n"
    result &= indentStr & parent & ".add(" & widgetName & ")\n"

# Main code generator - much simpler now
proc generateUingApp*(app: YuiApp): string =
  # Reset context
  ctx = CodeContext()
  
  var code = "import uing\nimport tables\n\n"
  code &= "# Generated from YAML-UI: " & app.app & "\n\n"
  
  # State type
  code &= "type AppState = object\n"
  if app.state.isSome:
    for name, stateVar in app.state.get.pairs:
      let nimType = nimTypeFromYamlNode(stateVar.value)
      code &= "  " & name & ": " & nimType & "\n"
  else:
    code &= "  dummy: int  # No state variables defined\n"
  
  code &= "\nvar appState = AppState()\n\n"
  
  # Initialize state
  if app.state.isSome:
    for name, stateVar in app.state.get.pairs:
      let nimValue = nimValueFromYamlNode(stateVar.value)
      code &= "appState." & name & " = " & nimValue & "\n"
  
  # Action handlers
  if app.actions.isSome:
    code &= "\n# Action handlers\n"
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
          code &= "  inc appState.counter\n"
        else: code &= "  echo \"increment called\"\n"
      of "decrement":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "  if appState.counter > 0: dec appState.counter\n"
        else: code &= "  echo \"decrement called\"\n"
      of "reset":
        if app.state.isSome:
          for name, stateVar in app.state.get.pairs:
            let defaultValue = nimValueFromYamlNode(stateVar.value)
            code &= "  appState." & name & " = " & defaultValue & "\n"
        else: code &= "  echo \"reset called\"\n"
      else:
        code &= "  echo \"" & actionName & " called\"\n"
      
      code &= "  refreshUI()\n\n"
  
  # UI creation
  code &= "proc createUI(): Window =\n"
  code &= "  result = newWindow(\"" & app.app & "\", 800, 600)\n"
  code &= "  let mainBox = newVerticalBox()\n"
  code &= "  mainBox.padded = true\n"
  code &= "  result.child = mainBox\n\n"
  
  # Walk the tree to generate UI
  for element in app.view:
    code &= visitElement(element, "mainBox", 1)
  
  code &= "\n  result.margined = true\n\n"
  
  # Generate refresh function
  code &= "proc refreshUI() =\n"
  if ctx.refreshStatements.len > 0:
    for stmt in ctx.refreshStatements:
      code &= stmt & "\n"
  else:
    code &= "  discard  # No dynamic widgets\n"
  
  # Main function
  code &= "\nproc main() =\n"
  code &= "  let app = newApp()\n"
  code &= "  let window = createUI()\n"
  code &= "  refreshUI()  # Set initial values\n"
  code &= "  window.show()\n"
  code &= "  app.run()\n\n"
  code &= "when isMainModule:\n"
  code &= "  main()\n"
  
  return code

# Function to parse YUI from file and generate uing code
proc generateUingFromYuiFile*(filepath: string): string =
  let app = yui_validator.loadAndValidateYuiFile(filepath).app
  return generateUingApp(app)

# Validate the generated uing app and report any issues
proc validateUingOutput*(code: string): seq[string] =
  var issues: seq[string] = @[]
  if not code.contains("import uing"): issues.add("Missing uing import")
  if not code.contains("proc main()"): issues.add("Missing main procedure")
  if not code.contains("newApp()"): issues.add("Missing app creation")
  if not code.contains("refreshUI()"): issues.add("Missing UI refresh mechanism")
  return issues

# Main function for CLI usage
when isMainModule:
  if paramCount() < 1:
    echo "Usage: yui_uing_generator <file.yui> [output.nim]"
    echo "Options:"
    echo "  --validate   Validate the YUI file before generating code"
    quit(1)
  
  let inputFile = paramStr(1)
  echo "Generating uing code from ", inputFile
  
  let validate = paramCount() >= 2 and paramStr(2) == "--validate"
  
  if validate:
    let validation = yui_validator.loadAndValidateYuiFile(inputFile)
    if validation.errors.len > 0:
      echo "YUI validation errors:"
      for error in validation.errors:
        echo "  - ", error
      quit(1)
  
  let uingCode = generateUingFromYuiFile(inputFile)
  
  let issues = validateUingOutput(uingCode)
  if issues.len > 0:
    echo "Warning: Potential issues in generated code:"
    for issue in issues:
      echo "  - ", issue
  
  let outputFile = if validate and paramCount() >= 3: paramStr(3) 
                   elif not validate and paramCount() >= 2: paramStr(2)
                   else: ""
  
  if outputFile != "":
    writeFile(outputFile, uingCode)
    echo "uing code written to ", outputFile
    echo "Compile with: nim c -r ", outputFile
  else:
    echo uingCode