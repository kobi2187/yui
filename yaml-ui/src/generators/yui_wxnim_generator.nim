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

# Simple context for code gen
type CodeContext = object
  eventBindings: seq[string]    # Event binding statements
  updateStatements: seq[string] # UI refresh statements
  widgetCounter: int

var ctx: CodeContext

# Figure out Nim type from YAML
proc nimTypeFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    if node.content == "true" or node.content == "false": return "bool"
    elif node.content.len > 0 and node.content.allCharsInSet(Digits + {'.', '-'}):
      if '.' in node.content: return "float64" else: return "int"
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
    of "bool", "int", "float64": return node.content
    else: return "\"" & node.content & "\""
  of ySequence:
    if node.elems.len == 0: return "@[]"
    var values: seq[string] = @[]
    for elem in node.elems:
      values.add(nimValueFromYamlNode(elem))
    return "@[" & values.join(", ") & "]"
  of yMapping: return "initTable[string, string]()"
  else: return "\"\""

# Extract state vars from strings like "Count: {counter}"
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

# Convert "Count: {counter}" to wxNim string concat
proc makeWxInterpolation(content: string): string =
  var result = content
  let vars = extractStateVars(content)
  for v in vars:
    result = result.replace("{" & v & "}", "\" & $self.state." & v & " & \"")
  return "\"" & result & "\""

# Generate unique widget names
proc nextWidgetName(elementType: string): string =
  result = elementType & $ctx.widgetCounter
  inc ctx.widgetCounter

# Main tree walker for wxNim
proc visitElement(element: Element, parent: string, indent: int): string =
  let indentStr = "  ".repeat(indent)
  let widgetName = if element.properties.id.isSome: element.properties.id.get else: nextWidgetName(element.elementType)
  
  case element.elementType:
  
  of "label":
    result = indentStr & "let " & widgetName & " = StaticText.new(" & parent
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        # Dynamic content - needs refresh
        let interpolated = makeWxInterpolation(content)
        result &= ", " & interpolated & ")\n"
        ctx.updateStatements.add("  " & widgetName & ".label = " & interpolated)
      else:
        result &= ", \"" & content & "\")\n"
    else:
      result &= ", \"Label\")\n"
  
  of "button":
    result = indentStr & "self." & widgetName & " = Button.new(" & parent
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        let interpolated = makeWxInterpolation(content)
        result &= ", " & interpolated & ")\n"
        ctx.updateStatements.add("  self." & widgetName & ".label = " & interpolated)
      else:
        result &= ", \"" & content & "\")\n"
    else:
      result &= ", \"Button\")\n"
    
    # Wire up click handler
    if element.events.hasKey("on_click"):
      let handler = element.events["on_click"].handler.split('/')[0]
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_BUTTON, proc(e: Event) = self." & handler & "())")
  
  of "input":
    result = indentStr & "self." & widgetName & " = TextCtrl.new(" & parent & ")\n"
    
    # Handle binding
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "self." & widgetName & ".value = $self.state." & bindProp & "\n"
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_TEXT, proc(e: Event) = self.state." & bindProp & " = self." & widgetName & ".value; self.updateUI())")
      ctx.updateStatements.add("  self." & widgetName & ".value = $self.state." & bindProp)
    
    # Handle placeholder as tooltip
    if element.rawProperties.hasKey("placeholder"):
      result &= indentStr & "self." & widgetName & ".toolTip = \"" & element.rawProperties["placeholder"].content & "\"\n"
  
  of "checkbox":
    result = indentStr & "self." & widgetName & " = CheckBox.new(" & parent
    if element.content.isSome:
      result &= ", \"" & element.content.get & "\")\n"
    else:
      result &= ", \"Checkbox\")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "self." & widgetName & ".value = self.state." & bindProp & "\n"
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_CHECKBOX, proc(e: Event) = self.state." & bindProp & " = self." & widgetName & ".value; self.updateUI())")
      ctx.updateStatements.add("  self." & widgetName & ".value = self.state." & bindProp)
  
  of "select":
    result = indentStr & "self." & widgetName & " = Choice.new(" & parent & ")\n"
    
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
          result &= indentStr & "self." & widgetName & ".append(\"" & labelText & "\")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_CHOICE, proc(e: Event) = if self." & widgetName & ".selection >= 0: self.state." & bindProp & " = self." & widgetName & ".stringSelection; self.updateUI())")
  
  of "textarea":
    result = indentStr & "self." & widgetName & " = TextCtrl.new(" & parent & ", style = TE_MULTILINE)\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "self." & widgetName & ".value = $self.state." & bindProp & "\n"
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_TEXT, proc(e: Event) = self.state." & bindProp & " = self." & widgetName & ".value; self.updateUI())")
      ctx.updateStatements.add("  self." & widgetName & ".value = $self.state." & bindProp)
  
  of "slider":
    var minVal = "0"
    var maxVal = "100"
    if element.rawProperties.hasKey("min"): minVal = element.rawProperties["min"].content
    if element.rawProperties.hasKey("max"): maxVal = element.rawProperties["max"].content
    
    result = indentStr & "self." & widgetName & " = Slider.new(" & parent & ", value = 0, minValue = " & minVal & ", maxValue = " & maxVal & ")\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "self." & widgetName & ".value = self.state." & bindProp & "\n"
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_SLIDER, proc(e: Event) = self.state." & bindProp & " = self." & widgetName & ".value; self.updateUI())")
      ctx.updateStatements.add("  self." & widgetName & ".value = self.state." & bindProp)
  
  of "progress":
    result = indentStr & "let " & widgetName & " = Gauge.new(" & parent & ", range = 100)\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & widgetName & ".value = self.state." & bindProp & "\n"
      ctx.updateStatements.add("  " & widgetName & ".value = self.state." & bindProp)
    elif element.rawProperties.hasKey("value"):
      let value = element.rawProperties["value"].content
      if value.startsWith("{") and value.endsWith("}"):
        let stateVar = value[1..^2].strip()
        result &= indentStr & widgetName & ".value = self.state." & stateVar & "\n"
        ctx.updateStatements.add("  " & widgetName & ".value = self.state." & stateVar)
  
  # Container widgets
  of "row":
    result = indentStr & "let " & widgetName & " = Panel.new(" & parent & ")\n"
    result &= indentStr & "let " & widgetName & "_sizer = BoxSizer.new(HORIZONTAL)\n"
    result &= indentStr & widgetName & ".sizer = " & widgetName & "_sizer\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName, indent + 1)
        let childName = if child.properties.id.isSome: child.properties.id.get else: nextWidgetName(child.elementType)
        result &= indentStr & "  " & widgetName & "_sizer.add(" & childName & ", 0, EXPAND | ALL, 5)\n"
    
    result &= indentStr & widgetName & ".layout()\n"
  
  of "column":
    result = indentStr & "let " & widgetName & " = Panel.new(" & parent & ")\n"
    result &= indentStr & "let " & widgetName & "_sizer = BoxSizer.new(VERTICAL)\n"
    result &= indentStr & widgetName & ".sizer = " & widgetName & "_sizer\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName, indent + 1)
        let childName = if child.properties.id.isSome: child.properties.id.get else: nextWidgetName(child.elementType)
        result &= indentStr & "  " & widgetName & "_sizer.add(" & childName & ", 0, EXPAND | ALL, 5)\n"
    
    result &= indentStr & widgetName & ".layout()\n"
  
  of "grid":
    # Parse grid dimensions
    var cols = 2
    var rows = 2
    if element.dimensions.isSome:
      let parts = element.dimensions.get.split('x')
      if parts.len > 0:
        try: cols = parseInt(parts[0])
        except: discard
      if parts.len > 1:
        try: rows = parseInt(parts[1])
        except: discard
    
    result = indentStr & "let " & widgetName & " = Panel.new(" & parent & ")\n"
    result &= indentStr & "let " & widgetName & "_sizer = FlexGridSizer.new(" & $rows & ", " & $cols & ", 5, 5)\n"
    result &= indentStr & widgetName & ".sizer = " & widgetName & "_sizer\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName, indent + 1)
        let childName = if child.properties.id.isSome: child.properties.id.get else: nextWidgetName(child.elementType)
        result &= indentStr & "  " & widgetName & "_sizer.add(" & childName & ", 0, EXPAND | ALL, 5)\n"
    
    result &= indentStr & widgetName & ".layout()\n"
  
  of "group":
    result = indentStr & "let " & widgetName & " = StaticBoxSizer.new(VERTICAL, " & parent
    if element.content.isSome:
      result &= ", \"" & element.content.get & "\")\n"
    else:
      result &= ", \"Group\")\n"
    
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, widgetName & ".staticBox", indent + 1)
        let childName = if child.properties.id.isSome: child.properties.id.get else: nextWidgetName(child.elementType)
        result &= indentStr & "  " & widgetName & ".add(" & childName & ", 0, EXPAND | ALL, 5)\n"
  
  of "tab":
    result = indentStr & "let " & widgetName & " = Notebook.new(" & parent & ")\n"
    
    if element.children.isSome:
      for i, child in element.children.get:
        if child.elementType == "tab":
          let pageId = widgetName & "_page" & $i
          result &= indentStr & "let " & pageId & " = Panel.new(" & widgetName & ")\n"
          
          if child.children.isSome:
            for tabChild in child.children.get:
              result &= visitElement(tabChild, pageId, indent + 1)
          
          let tabTitle = if child.content.isSome: child.content.get else: "Tab " & $(i+1)
          result &= indentStr & widgetName & ".addPage(" & pageId & ", \"" & tabTitle & "\")\n"
  
  of "table":
    result = indentStr & "self." & widgetName & " = ListCtrl.new(" & parent & ", style = LC_REPORT)\n"
    
    # Add columns
    if element.rawProperties.hasKey("columns") and element.rawProperties["columns"].kind == ySequence:
      var colIndex = 0
      for colNode in element.rawProperties["columns"]:
        if colNode.kind == yMapping:
          var headerText = "Column"
          var width = 100
          
          for pair in colNode.pairs:
            if pair[0].content == "header": headerText = pair[1].content
            elif pair[0].content == "width":
              try: width = parseInt(pair[1].content)
              except: width = 100
          
          result &= indentStr & "self." & widgetName & ".insertColumn(" & $colIndex & ", \"" & headerText & "\", width = " & $width & ")\n"
          inc colIndex
    
    # Handle selection events
    if element.events.hasKey("on_select"):
      let handler = element.events["on_select"].handler.split('/')[0]
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_LIST_ITEM_SELECTED, proc(e: ListEvent) = self." & handler & "(e.index))")
  
  of "tree":
    result = indentStr & "self." & widgetName & " = TreeCtrl.new(" & parent & ")\n"
    result &= indentStr & "let " & widgetName & "_root = self." & widgetName & ".addRoot(\"Root\")\n"
    
    if element.events.hasKey("on_select"):
      let handler = element.events["on_select"].handler.split('/')[0]
      ctx.eventBindings.add("  self." & widgetName & ".bind(EVT_TREE_SEL_CHANGED, proc(e: TreeEvent) = self." & handler & "(e.item))")
  
  else:
    # Fallback
    result = indentStr & "let " & widgetName & " = StaticText.new(" & parent & ", \"[" & element.elementType & "]\")\n"

# Main wxNim app generator
proc generateWxNimApp*(app: YuiApp): string =
  ctx = CodeContext()  # Reset context
  
  var code = """
import wx
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
  
  # Main frame class
  code &= """
# Main frame
type MainFrame = ref object of Frame
  state: AppState
"""
  
  # Add widget field declarations for widgets that need events/updates
  # We'll track these as we generate
  var widgetFields: seq[string] = @[]
  
  # Generate UI creation
  code &= """
proc newMainFrame(): MainFrame =
  result = MainFrame.new()
  result.init(title = """" & app.app & """", size = (800, 600))
  result.state = AppState()
"""
  
  # Initialize state
  if app.state.isSome:
    for name, stateVar in app.state.get.pairs:
      let nimValue = nimValueFromYamlNode(stateVar.value)
      code &= "  result.state." & name & " = " & nimValue & "\n"
  
  code &= """
  result.createControls()
  result.bindEvents()

proc createControls(self: MainFrame) =
  # Create main panel
  let mainPanel = Panel.new(self)
  let mainSizer = BoxSizer.new(VERTICAL)
  mainPanel.sizer = mainSizer

"""
  
  # Generate UI elements
  for element in app.view:
    code &= visitElement(element, "mainPanel", 1)
    let rootName = if element.properties.id.isSome: element.properties.id.get else: nextWidgetName(element.elementType)
    code &= "  mainSizer.add(" & rootName & ", 1, EXPAND | ALL, 5)\n"
  
  code &= """
  mainPanel.layout()

proc bindEvents(self: MainFrame) =
"""
  
  # Add event bindings
  if ctx.eventBindings.len > 0:
    for binding in ctx.eventBindings:
      code &= binding & "\n"
  else:
    code &= "  discard  # No events to bind\n"
  
  # Generate action handlers
  if app.actions.isSome:
    code &= "\n# Action handlers\n"
    for actionDef in app.actions.get:
      let parts = actionDef.split('/')
      let actionName = parts[0]
      var arity = 0
      if parts.len > 1:
        try: arity = parseInt(parts[1])
        except: discard
      
      code &= "proc " & actionName & "(self: MainFrame"
      if arity > 0: code &= ", value: auto"
      code &= ") =\n"
      
      # Common patterns
      case actionName:
      of "increment":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "  inc self.state.counter\n"
        else: code &= "  echo \"increment called\"\n"
      of "decrement":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "  if self.state.counter > 0: dec self.state.counter\n"
        else: code &= "  echo \"decrement called\"\n"
      of "reset":
        if app.state.isSome:
          for name, stateVar in app.state.get.pairs:
            let defaultValue = nimValueFromYamlNode(stateVar.value)
            code &= "  self.state." & name & " = " & defaultValue & "\n"
        else: code &= "  echo \"reset called\"\n"
      else:
        code &= "  echo \"" & actionName & " called\"\n"
      
      code &= "  self.updateUI()\n\n"
  
  # Generate UI update method
  code &= "proc updateUI(self: MainFrame) =\n"
  if ctx.updateStatements.len > 0:
    for stmt in ctx.updateStatements:
      code &= stmt & "\n"
  else:
    code &= "  discard  # No dynamic updates\n"
  
  # Main app
  code &= """
# Application class
type App = ref object of wx.App

proc onInit(self: App): bool =
  let frame = newMainFrame()
  frame.show()
  return true

proc main() =
  let app = App.new()
  app.run()

when isMainModule:
  main()
"""
  
  return code

# Function to parse YUI from file and generate wxNim code
proc generateWxNimFromYuiFile*(filepath: string): string =
  let app = yui_validator.loadAndValidateYuiFile(filepath).app
  return generateWxNimApp(app)

# Validate the generated wxNim app and report any issues
proc validateWxNimOutput*(code: string): seq[string] =
  var issues: seq[string] = @[]
  if not code.contains("import wx"): issues.add("Missing wx import")
  if not code.contains("type MainFrame"): issues.add("Missing MainFrame class")
  if not code.contains("proc main()"): issues.add("Missing main procedure")
  return issues

# Main function for CLI usage
when isMainModule:
  if paramCount() < 1:
    echo "Usage: yui_wxnim_generator <file.yui> [output.nim]"
    echo "Options:"
    echo "  --validate   Validate the YUI file before generating code"
    quit(1)
  
  let inputFile = paramStr(1)
  echo "Generating wxNim code from ", inputFile
  
  let validate = paramCount() >= 2 and paramStr(2) == "--validate"
  
  if validate:
    let validation = yui_validator.loadAndValidateYuiFile(inputFile)
    if validation.errors.len > 0:
      echo "YUI validation errors:"
      for error in validation.errors:
        echo "  - ", error
      quit(1)
  
  let wxnimCode = generateWxNimFromYuiFile(inputFile)
  
  let issues = validateWxNimOutput(wxnimCode)
  if issues.len > 0:
    echo "Warning: Potential issues in generated code:"
    for issue in issues:
      echo "  - ", issue
  
  let outputFile = if validate and paramCount() >= 3: paramStr(3) 
                   elif not validate and paramCount() >= 2: paramStr(2)
                   else: ""
  
  if outputFile != "":
    writeFile(outputFile, wxnimCode)
    echo "wxNim code written to ", outputFile
    echo "Compile with: nim c -r ", outputFile
  else:
    echo wxnimCode