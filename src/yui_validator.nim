import yaml
import tables, options, strutils, os
import sequtils, sets, sugar

# Type definitions for YAML-UI format
type
  BindDirection* = enum
    BiDirectional = "<->"
    ToView = "->"
    FromView = "<-"

  LayoutAlign* = enum
    AlignStart = "start"
    AlignCenter = "center"
    AlignEnd = "end"
    AlignStretch = "stretch"

  LayoutJustify* = enum
    JustifyStart = "start"
    JustifyCenter = "center"
    JustifyEnd = "end"
    JustifySpaceBetween = "spaceBetween"
    JustifySpaceAround = "spaceAround"
    JustifySpaceEvenly = "spaceEvenly"

  # State variable definition
  StateVar* = object
    value*: YamlNode  # We'll keep this as a YamlNode for flexibility

  # Binding definition
  Binding* = object
    direction*: BindDirection
    property*: string

  # Common properties for UI elements
  BaseProperties* = object
    id*: Option[string]
    width*: Option[string]
    height*: Option[string]
    grow*: Option[float]
    shrink*: Option[bool]
    align*: Option[LayoutAlign]
    justify*: Option[LayoutJustify]
    padding*: Option[string]
    margin*: Option[string]
    spacing*: Option[string]
    visible*: Option[string]
    enabled*: Option[bool]
    theme*: Option[string]
    font*: Option[string]
    color*: Option[string]
    backgroundColor*: Option[string]
    bind*: Option[Binding]

  # Event handler
  EventHandler* = object
    handler*: string  # Function name with arity (e.g., "handleClick/1")

  # UI Element
  Element* = ref object
    elementType*: string
    dimensions*: Option[string]  # Optional WxH format
    content*: Option[string]     # Optional content/text
    properties*: BaseProperties
    events*: TableRef[string, EventHandler]
    children*: Option[seq[Element]]
    rawProperties*: TableRef[string, YamlNode]  # For properties not covered by BaseProperties

  # Main application structure
  YuiApp* = object
    app*: string
    importTheme*: Option[string]
    state*: Option[TableRef[string, StateVar]]
    view*: seq[Element]
    actions*: Option[seq[string]]

# Helper function to parse binding string
proc parseBinding(bindStr: string): Binding =
  var direction = BiDirectional
  var property = bindStr.strip()
  
  # Check for explicit binding direction
  if bindStr.contains("<->"):
    direction = BiDirectional
    property = bindStr.replace("<->", "").strip()
  elif bindStr.contains("->"):
    direction = ToView
    property = bindStr.replace("->", "").strip()
  elif bindStr.contains("<-"):
    direction = FromView
    property = bindStr.replace("<-", "").strip()
  
  return Binding(direction: direction, property: property)

# Parse an element from a YAML node
proc parseElement(node: YamlNode): Element =
  result = new Element
  result.events = newTable[string, EventHandler]()
  result.rawProperties = newTable[string, YamlNode]()
  result.properties = BaseProperties()
  
  # First key is element type, possibly with dimensions and content
  let typeNode = node.pairs[0]
  let typeParts = typeNode[0].content.split()
  
  result.elementType = typeParts[0]
  
  # Check if dimensions are specified
  if typeParts.len > 1 and typeParts[1].contains('x'):
    result.dimensions = some(typeParts[1])
    # If there's content after dimensions, join the rest
    if typeParts.len > 2:
      result.content = some(typeParts[2..^1].join(" "))
  # If no dimensions but content exists
  elif typeParts.len > 1:
    result.content = some(typeParts[1..^1].join(" "))
  
  # Process properties
  if typeNode[1].kind == yScalar:
    # Simple element with no properties
    return result
  
  for prop in typeNode[1].pairs:
    let key = prop[0].content
    let value = prop[1]
    
    # Handle standard properties
    case key:
    of "id":
      result.properties.id = some(value.content)
    of "width":
      result.properties.width = some(value.content)
    of "height":
      result.properties.height = some(value.content)
    of "grow":
      if value.kind == yScalar:
        if value.content == "true":
          result.properties.grow = some(1.0)
        elif value.content == "false":
          result.properties.grow = some(0.0)
        else:
          result.properties.grow = some(parseFloat(value.content))
    of "shrink":
      result.properties.shrink = some(value.content == "true")
    of "align":
      result.properties.align = some(parseEnum[LayoutAlign](value.content))
    of "justify":
      result.properties.justify = some(parseEnum[LayoutJustify](value.content))
    of "padding":
      result.properties.padding = some(value.content)
    of "margin":
      result.properties.margin = some(value.content)
    of "spacing":
      result.properties.spacing = some(value.content)
    of "visible":
      result.properties.visible = some(value.content)
    of "enabled":
      result.properties.enabled = some(value.content == "true")
    of "theme":
      result.properties.theme = some(value.content)
    of "font":
      result.properties.font = some(value.content)
    of "color":
      result.properties.color = some(value.content)
    of "backgroundColor":
      result.properties.backgroundColor = some(value.content)
    of "bind":
      result.properties.bind = some(parseBinding(value.content))
    of "children":
      # Parse child elements
      if value.kind == ySequence:
        var children: seq[Element] = @[]
        for childNode in value:
          children.add(parseElement(childNode))
        result.children = some(children)
    else:
      # Handle event handlers (prefixed with "on_")
      if key.startsWith("on_"):
        let handler = EventHandler(handler: value.content)
        result.events[key] = handler
      else:
        # Store other properties as raw properties
        result.rawProperties[key] = value
  
  return result

# Parse the YUI application
proc parseYuiApp*(yamlContent: string): YuiApp =
  var yamlNode = loadAs(yamlContent, YamlNode)
  result = YuiApp()
  
  # Process top-level elements
  for topLevelPair in yamlNode.pairs:
    let key = topLevelPair[0].content
    let value = topLevelPair[1]
    
    case key:
    of "app":
      result.app = value.content
    of "import_theme":
      result.importTheme = some(value.content)
    of "state":
      var stateTable = newTable[string, StateVar]()
      for statePair in value.pairs:
        let stateName = statePair[0].content
        stateTable[stateName] = StateVar(value: statePair[1])
      result.state = some(stateTable)
    of "view":
      var elements: seq[Element] = @[]
      for elementNode in value:
        elements.add(parseElement(elementNode))
      result.view = elements
    of "actions":
      var actions: seq[string] = @[]
      for actionNode in value:
        actions.add(actionNode.content)
      result.actions = some(actions)

# Validate a YUI application
proc validateYuiApp*(app: YuiApp): seq[string] =
  var errors: seq[string] = @[]
  
  # Check required fields
  if app.app == "":
    errors.add("App name is required")
  
  if app.view.len == 0:
    errors.add("View must contain at least one element")
  
  # Check for valid action references
  let availableActions = if app.actions.isSome: app.actions.get.toHashSet else: initHashSet[string]()
  
  # Function to validate elements recursively
  proc validateElement(element: Element, path: string) =
    # Check for required properties
    if element.elementType == "":
      errors.add(path & ": Element type is required")
    
    # Validate event handlers reference valid actions
    for eventName, handler in element.events.pairs:
      if not availableActions.contains(handler.handler) and app.actions.isSome:
        errors.add(path & ": Event handler '" & handler.handler & 
                  "' referenced by '" & eventName & "' is not declared in actions")
    
    # Validate children
    if element.children.isSome:
      for i, child in element.children.get.pairs:
        validateElement(child, path & "." & element.elementType & "[" & $i & "]")
  
  # Start validation from root elements
  for i, element in app.view:
    validateElement(element, "view[" & $i & "]")
  
  return errors

# Function to load and validate a YUI file
proc loadAndValidateYuiFile*(filepath: string): tuple[app: YuiApp, errors: seq[string]] =
  let content = readFile(filepath)
  let app = parseYuiApp(content)
  let errors = validateYuiApp(app)
  return (app: app, errors: errors)

# Function to resolve theme references
proc resolveThemeReferences*(app: YuiApp): YuiApp =
  # Here we would load the theme file and resolve references like $colors.primary
  # This is a placeholder for the actual implementation
  return app

# Example usage
when isMainModule:
  if paramCount() < 1:
    echo "Usage: yui_validator <file.yui>"
    quit(1)
  
  let filepath = paramStr(1)
  echo "Validating ", filepath
  
  let result = loadAndValidateYuiFile(filepath)
  
  if result.errors.len > 0:
    echo "Validation errors:"
    for error in result.errors:
      echo "  - ", error
    quit(1)
  else:
    echo "File is valid!"
    
    # Print summary
    echo "\nApplication: ", result.app.app
    
    if result.app.importTheme.isSome:
      echo "Imports theme: ", result.app.importTheme.get
    
    if result.app.state.isSome:
      echo "State variables:"
      for name, _ in result.app.state.get:
        echo "  - ", name
    
    echo "UI Elements: ", result.app.view.len
    
    if result.app.actions.isSome:
      echo "Actions:"
      for action in result.app.actions.get:
        echo "  - ", action
    
    echo "\nValid YAML-UI file!"