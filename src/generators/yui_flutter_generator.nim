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
  stateUpdates: seq[string]   # setState calls for refreshing UI
  widgetCounter: int

var ctx: CodeContext

# Figure out Dart type from YAML
proc dartTypeFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    if node.content == "true" or node.content == "false": return "bool"
    elif node.content.len > 0 and node.content.allCharsInSet(Digits + {'.', '-'}):
      if '.' in node.content: return "double" else: return "int"
    else: return "String"
  of ySequence: return "List<dynamic>"
  of yMapping: return "Map<String, dynamic>"
  else: return "dynamic"

# Convert YAML to Dart literal
proc dartValueFromYamlNode(node: YamlNode): string =
  case node.kind
  of yScalar:
    let dartType = dartTypeFromYamlNode(node)
    case dartType
    of "String": return "'" & node.content & "'"
    of "bool", "int", "double": return node.content
    else: return "'" & node.content & "'"
  of ySequence:
    if node.elems.len == 0: return "[]"
    var values: seq[string] = @[]
    for elem in node.elems:
      values.add(dartValueFromYamlNode(elem))
    return "[" & values.join(", ") & "]"
  of yMapping: return "{}"
  else: return "''"

# Extract state vars from interpolated strings
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

# Convert "Count: {counter}" to Flutter string interpolation
proc makeFlutterInterpolation(content: string): string =
  var result = content
  let vars = extractStateVars(content)
  for v in vars:
    result = result.replace("{" & v & "}", "$" & v)
  return "'" & result & "'"

# Map layout properties to Flutter
proc flutterMainAxisAlignment(justify: LayoutJustify): string =
  case justify
  of JustifyStart: "MainAxisAlignment.start"
  of JustifyCenter: "MainAxisAlignment.center"
  of JustifyEnd: "MainAxisAlignment.end"
  of JustifySpaceBetween: "MainAxisAlignment.spaceBetween"
  of JustifySpaceAround: "MainAxisAlignment.spaceAround"
  of JustifySpaceEvenly: "MainAxisAlignment.spaceEvenly"

proc flutterCrossAxisAlignment(align: LayoutAlign): string =
  case align
  of AlignStart: "CrossAxisAlignment.start"
  of AlignCenter: "CrossAxisAlignment.center"
  of AlignEnd: "CrossAxisAlignment.end"
  of AlignStretch: "CrossAxisAlignment.stretch"

# Generate unique widget names when needed
proc nextWidgetName(): string =
  result = "widget" & $ctx.widgetCounter
  inc ctx.widgetCounter

# Main tree walker - each widget knows how to make itself
proc visitElement(element: Element, indent: int): string =
  let indentStr = "  ".repeat(indent)
  
  case element.elementType:
  
  of "label":
    result = indentStr & "Text(\n"
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        result &= indentStr & "  " & makeFlutterInterpolation(content) & ",\n"
      else:
        result &= indentStr & "  '" & content & "',\n"
    else:
      result &= indentStr & "  'Text',\n"
    
    # Handle styling if present
    if element.properties.font.isSome or element.properties.color.isSome:
      result &= indentStr & "  style: TextStyle(\n"
      if element.properties.font.isSome:
        # Parse "Roboto 16 bold" format
        let fontParts = element.properties.font.get.split()
        if fontParts.len >= 2: result &= indentStr & "    fontSize: " & fontParts[1] & ",\n"
        if fontParts.len >= 3 and fontParts[2] == "bold": result &= indentStr & "    fontWeight: FontWeight.bold,\n"
      result &= indentStr & "  ),\n"
    
    result &= indentStr & ")"
  
  of "button":
    result = indentStr & "ElevatedButton(\n"
    
    # Handle click events
    if element.events.hasKey("on_click"):
      let handler = element.events["on_click"].handler.split('/')[0]
      result &= indentStr & "  onPressed: () => " & handler & "(),\n"
    else:
      result &= indentStr & "  onPressed: () {},\n"
    
    # Button content
    result &= indentStr & "  child: "
    if element.content.isSome:
      let content = element.content.get
      if content.contains("{"):
        result &= "Text(" & makeFlutterInterpolation(content) & "),\n"
      else:
        result &= "Text('" & content & "'),\n"
    else:
      result &= "Text('Button'),\n"
    
    result &= indentStr & ")"
  
  of "input":
    result = indentStr & "TextField(\n"
    
    # Handle binding
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  controller: TextEditingController(text: " & bindProp & "),\n"
      result &= indentStr & "  onChanged: (value) {\n"
      result &= indentStr & "    setState(() {\n"
      result &= indentStr & "      " & bindProp & " = value;\n"
      result &= indentStr & "    });\n"
      result &= indentStr & "  },\n"
    
    # Handle placeholder
    if element.rawProperties.hasKey("placeholder"):
      result &= indentStr & "  decoration: InputDecoration(\n"
      result &= indentStr & "    hintText: '" & element.rawProperties["placeholder"].content & "',\n"
      result &= indentStr & "  ),\n"
    
    result &= indentStr & ")"
  
  of "checkbox":
    result = indentStr
    # If there's content, wrap with Row
    if element.content.isSome:
      result &= "Row(\n"
      result &= indentStr & "  children: [\n"
      result &= indentStr & "    Checkbox(\n"
    else:
      result &= "Checkbox(\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: " & bindProp & ",\n"
      result &= indentStr & "  onChanged: (value) {\n"
      result &= indentStr & "    setState(() {\n"
      result &= indentStr & "      " & bindProp & " = value!;\n"
      result &= indentStr & "    });\n"
      result &= indentStr & "  },\n"
    else:
      result &= indentStr & "  value: false,\n"
      result &= indentStr & "  onChanged: (_) {},\n"
    
    if element.content.isSome:
      result &= indentStr & "    ),\n"
      result &= indentStr & "    Text('" & element.content.get & "'),\n"
      result &= indentStr & "  ],\n"
      result &= indentStr & ")"
    else:
      result &= indentStr & ")"
  
  of "select":
    result = indentStr & "DropdownButton<String>(\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: " & bindProp & ",\n"
      result &= indentStr & "  onChanged: (value) {\n"
      result &= indentStr & "    setState(() {\n"
      result &= indentStr & "      " & bindProp & " = value!;\n"
      result &= indentStr & "    });\n"
      result &= indentStr & "  },\n"
    
    # Handle options
    result &= indentStr & "  items: [\n"
    if element.rawProperties.hasKey("options") and element.rawProperties["options"].kind == ySequence:
      for optionNode in element.rawProperties["options"]:
        var labelText = ""
        var valueText = ""
        if optionNode.kind == yMapping:
          for pair in optionNode.pairs:
            if pair[0].content == "label": labelText = pair[1].content
            elif pair[0].content == "value": valueText = pair[1].content
        elif optionNode.kind == yScalar:
          labelText = optionNode.content
          valueText = optionNode.content
        
        if labelText != "":
          result &= indentStr & "    DropdownMenuItem<String>(\n"
          result &= indentStr & "      value: '" & valueText & "',\n"
          result &= indentStr & "      child: Text('" & labelText & "'),\n"
          result &= indentStr & "    ),\n"
    result &= indentStr & "  ],\n"
    result &= indentStr & ")"
  
  of "slider":
    result = indentStr & "Slider(\n"
    
    var minVal = "0.0"
    var maxVal = "100.0"
    if element.rawProperties.hasKey("min"): minVal = element.rawProperties["min"].content & ".0"
    if element.rawProperties.hasKey("max"): maxVal = element.rawProperties["max"].content & ".0"
    
    result &= indentStr & "  min: " & minVal & ",\n"
    result &= indentStr & "  max: " & maxVal & ",\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: " & bindProp & ".toDouble(),\n"
      result &= indentStr & "  onChanged: (value) {\n"
      result &= indentStr & "    setState(() {\n"
      result &= indentStr & "      " & bindProp & " = value.toInt();\n"
      result &= indentStr & "    });\n"
      result &= indentStr & "  },\n"
    else:
      result &= indentStr & "  value: 50.0,\n"
      result &= indentStr & "  onChanged: (_) {},\n"
    
    result &= indentStr & ")"
  
  of "progress":
    result = indentStr & "LinearProgressIndicator(\n"
    
    if element.properties.bind.isSome:
      let bindProp = element.properties.bind.get.property
      result &= indentStr & "  value: " & bindProp & " / 100.0,\n"
    elif element.rawProperties.hasKey("value"):
      let value = element.rawProperties["value"].content
      if value.startsWith("{") and value.endsWith("}"):
        let stateVar = value[1..^2].strip()
        result &= indentStr & "  value: " & stateVar & " / 100.0,\n"
    
    result &= indentStr & ")"
  
  # Container widgets - create container and visit children
  of "row":
    result = indentStr & "Row(\n"
    
    if element.properties.justify.isSome:
      result &= indentStr & "  mainAxisAlignment: " & flutterMainAxisAlignment(element.properties.justify.get) & ",\n"
    if element.properties.align.isSome:
      result &= indentStr & "  crossAxisAlignment: " & flutterCrossAxisAlignment(element.properties.align.get) & ",\n"
    
    result &= indentStr & "  children: [\n"
    if element.children.isSome:
      for i, child in element.children.get:
        result &= visitElement(child, indent + 2) & ",\n"
        # Add spacing between elements
        if i < element.children.get.high and element.properties.spacing.isSome:
          result &= indentStr & "    SizedBox(width: " & element.properties.spacing.get & "),\n"
    result &= indentStr & "  ],\n"
    result &= indentStr & ")"
  
  of "column":
    result = indentStr & "Column(\n"
    
    if element.properties.justify.isSome:
      result &= indentStr & "  mainAxisAlignment: " & flutterMainAxisAlignment(element.properties.justify.get) & ",\n"
    if element.properties.align.isSome:
      result &= indentStr & "  crossAxisAlignment: " & flutterCrossAxisAlignment(element.properties.align.get) & ",\n"
    
    result &= indentStr & "  children: [\n"
    if element.children.isSome:
      for i, child in element.children.get:
        result &= visitElement(child, indent + 2) & ",\n"
        # Add spacing between elements
        if i < element.children.get.high and element.properties.spacing.isSome:
          result &= indentStr & "    SizedBox(height: " & element.properties.spacing.get & "),\n"
    result &= indentStr & "  ],\n"
    result &= indentStr & ")"
  
  of "grid":
    # Parse grid dimensions
    var columns = 2
    if element.dimensions.isSome:
      let parts = element.dimensions.get.split('x')
      if parts.len > 0:
        try: columns = parseInt(parts[0])
        except: discard
    
    result = indentStr & "GridView.count(\n"
    result &= indentStr & "  crossAxisCount: " & $columns & ",\n"
    result &= indentStr & "  shrinkWrap: true,\n"
    
    if element.properties.spacing.isSome:
      result &= indentStr & "  mainAxisSpacing: " & element.properties.spacing.get & ",\n"
      result &= indentStr & "  crossAxisSpacing: " & element.properties.spacing.get & ",\n"
    
    result &= indentStr & "  children: [\n"
    if element.children.isSome:
      for child in element.children.get:
        result &= visitElement(child, indent + 2) & ",\n"
    result &= indentStr & "  ],\n"
    result &= indentStr & ")"
  
  of "tab":
    result = indentStr & "DefaultTabController(\n"
    let tabCount = if element.children.isSome: element.children.get.len else: 1
    result &= indentStr & "  length: " & $tabCount & ",\n"
    result &= indentStr & "  child: Column(\n"
    result &= indentStr & "    children: [\n"
    result &= indentStr & "      TabBar(\n"
    result &= indentStr & "        tabs: [\n"
    
    # Tab headers
    if element.children.isSome:
      for child in element.children.get:
        let tabTitle = if child.content.isSome: child.content.get else: "Tab"
        result &= indentStr & "          Tab(text: '" & tabTitle & "'),\n"
    
    result &= indentStr & "        ],\n"
    result &= indentStr & "      ),\n"
    result &= indentStr & "      Expanded(\n"
    result &= indentStr & "        child: TabBarView(\n"
    result &= indentStr & "          children: [\n"
    
    # Tab content
    if element.children.isSome:
      for child in element.children.get:
        result &= indentStr & "            Column(\n"
        result &= indentStr & "              children: [\n"
        if child.children.isSome:
          for tabChild in child.children.get:
            result &= visitElement(tabChild, indent + 8) & ",\n"
        result &= indentStr & "              ],\n"
        result &= indentStr & "            ),\n"
    
    result &= indentStr & "          ],\n"
    result &= indentStr & "        ),\n"
    result &= indentStr & "      ),\n"
    result &= indentStr & "    ],\n"
    result &= indentStr & "  ),\n"
    result &= indentStr & ")"
  
  else:
    # Fallback for unsupported elements
    result = indentStr & "Container(\n"
    result &= indentStr & "  child: Text('[" & element.elementType & "]'),\n"
    result &= indentStr & ")"

# Main Flutter app generator
proc generateFlutterApp*(app: YuiApp): string =
  ctx = CodeContext()  # Reset context
  
  var code = """
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '""" & app.app & """',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
"""

  # Generate state variables
  if app.state.isSome:
    for name, stateVar in app.state.get.pairs:
      let dartType = dartTypeFromYamlNode(stateVar.value)
      let dartValue = dartValueFromYamlNode(stateVar.value)
      code &= "  " & dartType & " " & name & " = " & dartValue & ";\n"
  
  # Generate action methods
  if app.actions.isSome:
    code &= "\n"
    for actionDef in app.actions.get:
      let parts = actionDef.split('/')
      let actionName = parts[0]
      var arity = 0
      if parts.len > 1:
        try: arity = parseInt(parts[1])
        except: discard
      
      code &= "  void " & actionName & "("
      if arity > 0: code &= "dynamic value"
      code &= ") {\n"
      code &= "    setState(() {\n"
      
      # Common patterns
      case actionName:
      of "increment":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "      counter++;\n"
        else: code &= "      // TODO: Implement increment\n"
      of "decrement":
        if app.state.isSome and app.state.get.hasKey("counter"):
          code &= "      if (counter > 0) counter--;\n"
        else: code &= "      // TODO: Implement decrement\n"
      of "reset":
        if app.state.isSome:
          for name, stateVar in app.state.get.pairs:
            let defaultValue = dartValueFromYamlNode(stateVar.value)
            code &= "      " & name & " = " & defaultValue & ";\n"
        else: code &= "      // TODO: Implement reset\n"
      else:
        code &= "      // TODO: Implement " & actionName & "\n"
      
      code &= "    });\n"
      code &= "  }\n\n"
  
  # Build method
  code &= """
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('""" & app.app & """'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: """
  
  # Generate UI tree
  if app.view.len > 0:
    if app.view.len == 1:
      code &= visitElement(app.view[0], 4)
    else:
      # Multiple root elements - wrap in Column
      code &= "Column(\n"
      code &= "          children: [\n"
      for element in app.view:
        code &= visitElement(element, 6) & ",\n"
      code &= "          ],\n"
      code &= "        )"
  else:
    code &= "Container()"
  
  code &= """
      ),
    );
  }
}
"""
  
  return code

# Function to parse YUI from file and generate Flutter code
proc generateFlutterFromYuiFile*(filepath: string): string =
  let app = yui_validator.loadAndValidateYuiFile(filepath).app
  return generateFlutterApp(app)

# Validate the generated Flutter app and report any issues
proc validateFlutterOutput*(code: string): seq[string] =
  var issues: seq[string] = @[]
  if not code.contains("void main()"): issues.add("Missing main function")
  if not code.contains("runApp("): issues.add("Missing runApp call")
  if not code.contains("class MyApp extends StatelessWidget"): issues.add("Missing StatelessWidget app class")
  if not code.contains("class MyHomePage extends StatefulWidget"): issues.add("Missing StatefulWidget page class")
  return issues

# Main function for CLI usage
when isMainModule:
  if paramCount() < 1:
    echo "Usage: yui_flutter_generator <file.yui> [output.dart]"
    echo "Options:"
    echo "  --validate   Validate the YUI file before generating code"
    quit(1)
  
  let inputFile = paramStr(1)
  echo "Generating Flutter code from ", inputFile
  
  let validate = paramCount() >= 2 and paramStr(2) == "--validate"
  
  if validate:
    let validation = yui_validator.loadAndValidateYuiFile(inputFile)
    if validation.errors.len > 0:
      echo "YUI validation errors:"
      for error in validation.errors:
        echo "  - ", error
      quit(1)
  
  let flutterCode = generateFlutterFromYuiFile(inputFile)
  
  let issues = validateFlutterOutput(flutterCode)
  if issues.len > 0:
    echo "Warning: Potential issues in generated code:"
    for issue in issues:
      echo "  - ", issue
  
  let outputFile = if validate and paramCount() >= 3: paramStr(3) 
                   elif not validate and paramCount() >= 2: paramStr(2)
                   else: ""
  
  if outputFile != "":
    writeFile(outputFile, flutterCode)
    echo "Flutter code written to ", outputFile
    echo "Run with: flutter run -t ", outputFile
  else:
    echo flutterCode