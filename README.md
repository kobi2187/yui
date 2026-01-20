# YAML-UI: A Portable GUI Description Format

YAML-UI (`.yui`) is a human-readable, declarative format for describing graphical user interfaces that can be used across multiple platforms and UI toolkits. It provides a unified way to define UI structure, layout, and behavior while generating native code for different frameworks.

## Core Concepts

YAML-UI is built around a few key principles:

1. **Human Readability**: Clear, concise syntax that's easy to understand at a glance
2. **Declarative Structure**: Describe what the UI should be, not how to build it
3. **Cross-Platform**: Generate UI code for multiple platforms from a single description
4. **Toolkit-Agnostic**: Not tied to any specific UI framework
5. **Separation of UI and Logic**: Clean division between interface and application code

## Basic Structure

A YAML-UI file consists of several main sections:

```yaml
# Application metadata
app: "My Application"
import_theme: "theme.yui"  # Optional theme import

# State variables
state:
  counter: 0
  username: ""
  isLoggedIn: false

# UI structure
view:
  - column:
      # UI elements go here
      children:
        - label "Hello World"
        - button "Click Me":
            on_click: handleClick/0

# Action references
actions:
  - handleClick/0
  - updateUsername/1
```

## State Management

The `state` section defines variables used throughout the UI:

```yaml
state:
  counter: 0              # Number type inferred from value
  name: ""                # String type inferred from value
  isVisible: true         # Boolean type inferred from value
  items: []               # Array type
  settings: {}            # Object type
```

## Layout Elements

YAML-UI provides a set of standard container elements to control layout:

### Row

Arranges children horizontally:

```yaml
- row:
    spacing: 8            # Space between children
    align: center         # Vertical alignment (start, center, end, stretch)
    justify: spaceBetween # Horizontal distribution
    padding: 16px         # Padding around content
    children:
      - button "Cancel"
      - button "OK"
```

### Column

Arranges children vertically:

```yaml
- column:
    spacing: 16           # Space between children
    align: stretch        # Horizontal alignment (start, center, end, stretch)
    justify: start        # Vertical distribution
    padding: 24px 16px    # Padding (top/bottom left/right)
    children:
      - label "Username"
      - input:
          bind <-> username
```

### Grid

Arranges children in a grid layout:

```yaml
- grid 3x2:               # 3 columns, 2 rows
    spacing: [16, 8]      # [horizontal, vertical] spacing
    children:
      - label "Name:"
      - input:
          bind <-> name
      - label "Email:"
      - input:
          bind <-> email
      - label "Password:"
      - password:
          bind <-> password
```

### Tab

Creates a tabbed interface:

```yaml
- tab:
    children:
      - tab "General":
          children:
            - label "General Settings"
            - checkbox "Enable feature":
                bind <-> settings.enableFeature
      - tab "Advanced":
          children:
            - label "Advanced Settings"
            - input:
                bind <-> settings.apiKey
```

### Pane

Creates a split pane with an adjustable divider:

```yaml
- pane horizontal:
    dividerPosition: 0.3  # 30% for first panel
    children:
      - tree:              # Left panel
          data: "{fileTree}"
      - textarea:          # Right panel
          bind <-> fileContent
```

### Scroll

Creates a scrollable container:

```yaml
- scroll:
    children:
      - column:
          children:
            # Lots of content here...
```

### Group

Visual grouping with optional title:

```yaml
- group "User Information":
    children:
      - label "Name: {user.name}"
      - label "Email: {user.email}"
```

## UI Widgets

YAML-UI supports a standard set of widgets found in most UI toolkits:

### Label

Displays static text:

```yaml
- label "Hello World":
    font: $fonts.title
    color: $colors.primary
```

### Button

Clickable control:

```yaml
- button "Save":
    on_click: saveData/0
    enabled: "{isFormValid}"
    theme: "button.primary"
```

### Input

Text entry field:

```yaml
- input:
    bind <-> username
    placeholder: "Enter username"
    size: 200x40
```

### Checkbox

Boolean toggle control:

```yaml
- checkbox "Remember me":
    bind <-> rememberLogin
```

### Radio

Exclusive selection from a group:

```yaml
- radio "Option 1":
    bind <-> selectedOption
    value: "option1"
- radio "Option 2":
    bind <-> selectedOption
    value: "option2"
```

### Select

Dropdown selection:

```yaml
- select:
    bind <-> country
    options:
      - value: "us"
        label: "United States"
      - value: "ca"
        label: "Canada"
      - value: "mx"
        label: "Mexico"
```

### Textarea

Multi-line text input:

```yaml
- textarea:
    bind <-> notes
    placeholder: "Enter notes here"
    size: 400x200
```

### Slider

Value selection along a range:

```yaml
- slider:
    bind <-> volume
    min: 0
    max: 100
    step: 1
```

### Progress

Progress indicator:

```yaml
- progress:
    value: "{loadingProgress}"
    max: 100
```

### Image

Image display:

```yaml
- image:
    source: "logo.png"
    size: 240x80
```

### Table

Tabular data display:

```yaml
- table:
    data: "{users}"
    columns:
      - field: "id"
        header: "ID"
        width: 60
      - field: "name"
        header: "Name"
        grow: 1
      - field: "email"
        header: "Email"
        width: 200
    on_select: selectUser/1
```

### Tree

Hierarchical data display:

```yaml
- tree:
    data: "{fileTree}"
    on_select: selectFile/1
```

### List

List of items:

```yaml
- list:
    data: "{items}"
    template: label "{item.name}"
    on_select: selectItem/1
```

## Data Binding

YAML-UI supports different binding directions:

```yaml
# Bidirectional (UI to state and state to UI)
bind <-> username

# One-way state to UI
bind -> displayName

# One-way UI to state
bind <- inputValue
```

String interpolation for dynamic content:

```yaml
- label "Hello, {username}!"
- button "Count: {counter}"
```

Conditional expressions:

```yaml
- button "Login":
    visible: "{!isLoggedIn}"
- label "Welcome back!":
    visible: "{isLoggedIn}"
```

# Theme System

YAML-UI includes a powerful theming system that separates design values from UI structure. This approach allows you to:

1. Create consistent visual designs across your application
2. Switch themes (light/dark, branded variations) without changing UI code
3. Reuse design tokens across multiple applications
4. Centralize design decisions in one place

## Theme Structure

A theme is defined in a separate `.yui` file with this basic structure:

```yaml
# theme.yui
theme:
  # Color palette
  colors:
    primary: "#4285F4"
    secondary: "#34A853"
    accent: "#FBBC05"
    danger: "#EA4335"
    
    text:
      primary: "#202124"
      secondary: "#5F6368"
      disabled: "#9AA0A6"
    
    background:
      primary: "#FFFFFF"
      secondary: "#F1F3F4"
      tertiary: "#E8EAED"
  
  # Typography
  fonts:
    title: "Roboto 24 bold"
    heading: "Roboto 18 medium"
    body: "Roboto 16"
    small: "Roboto 14"
    
  # Sizing
  sizes:
    icon:
      small: 16x16
      medium: 24x24
      large: 32x32
    
    button:
      small: 80x32
      medium: 120x40
      large: 160x48
    
    input:
      small: 200x32
      medium: 320x40
      large: 480x48
  
  # Spacing scale
  spacing:
    xs: 4
    sm: 8
    md: 16
    lg: 24
    xl: 32
  
  # Padding presets
  padding:
    container: 24px 16px
    panel: 16px
    card: 16px
    input: 8px 12px
    
  # Border radius scale
  radius:
    sm: 2
    md: 4
    lg: 8
    pill: 999

  # Component-specific styling
  button:
    # Base styles for all buttons
    base:
      borderRadius: $radius.md
      fontWeight: 500
      
    # Primary button style
    primary:
      extends: "button.base"
      backgroundColor: $colors.primary
      color: "#FFFFFF"
    
    # Secondary button style  
    secondary:
      extends: "button.base"
      backgroundColor: $colors.secondary
      color: "#FFFFFF"
    
    # Danger/warning button
    danger:
      extends: "button.base"
      backgroundColor: $colors.danger
      color: "#FFFFFF"
    
    # Text-only button
    text:
      extends: "button.base"
      backgroundColor: "transparent"
      color: $colors.primary
  
  # Input field styling
  input:
    base:
      borderRadius: $radius.md
      borderColor: "#CCCCCC"
      padding: $padding.input
    
    search:
      extends: "input.base"
      iconLeft: "search"
      backgroundColor: $colors.background.secondary
```

## Theme Inheritance

Themes can inherit from other themes, allowing you to create variations without duplicating values:

```yaml
# dark_theme.yui
import_theme: "base_theme.yui"

theme:
  # Override only what needs to change
  colors:
    primary: "#8AB4F8"  # Lighter blue for dark theme
    
    text:
      primary: "#E8EAED"  # Light text for dark background
      secondary: "#9AA0A6"
    
    background:
      primary: "#202124"  # Dark background
      secondary: "#303134"
```

## Using Themes

To use a theme in your UI, import it at the top of your YAML-UI file:

```yaml
app: "My Application"
import_theme: "themes/brand_theme.yui"

# Rest of your UI definition...
```

## Theme References

You can reference theme values throughout your UI using the `# YAML-UI: A Portable GUI Description Format

YAML-UI (`.yui`) is a human-readable, declarative format for describing graphical user interfaces that can be used across multiple platforms and UI toolkits. It provides a unified way to define UI structure, layout, and behavior while generating native code for different frameworks.

## Core Concepts

YAML-UI is built around a few key principles:

1. **Human Readability**: Clear, concise syntax that's easy to understand at a glance
2. **Declarative Structure**: Describe what the UI should be, not how to build it
3. **Cross-Platform**: Generate UI code for multiple platforms from a single description
4. **Toolkit-Agnostic**: Not tied to any specific UI framework
5. **Separation of UI and Logic**: Clean division between interface and application code

## Basic Structure

A YAML-UI file consists of several main sections:

```yaml
# Application metadata
app: "My Application"
import_theme: "theme.yui"  # Optional theme import

# State variables
state:
  counter: 0
  username: ""
  isLoggedIn: false

# UI structure
view:
  - column:
      # UI elements go here
      children:
        - label "Hello World"
        - button "Click Me":
            on_click: handleClick/0

# Action references
actions:
  - handleClick/0
  - updateUsername/1
```

## State Management

The `state` section defines variables used throughout the UI:

```yaml
state:
  counter: 0              # Number type inferred from value
  name: ""                # String type inferred from value
  isVisible: true         # Boolean type inferred from value
  items: []               # Array type
  settings: {}            # Object type
```

## Layout Elements

YAML-UI provides a set of standard container elements to control layout:

### Row

Arranges children horizontally:

```yaml
- row:
    spacing: 8            # Space between children
    align: center         # Vertical alignment (start, center, end, stretch)
    justify: spaceBetween # Horizontal distribution
    padding: 16px         # Padding around content
    children:
      - button "Cancel"
      - button "OK"
```

### Column

Arranges children vertically:

```yaml
- column:
    spacing: 16           # Space between children
    align: stretch        # Horizontal alignment (start, center, end, stretch)
    justify: start        # Vertical distribution
    padding: 24px 16px    # Padding (top/bottom left/right)
    children:
      - label "Username"
      - input:
          bind <-> username
```

### Grid

Arranges children in a grid layout:

```yaml
- grid 3x2:               # 3 columns, 2 rows
    spacing: [16, 8]      # [horizontal, vertical] spacing
    children:
      - label "Name:"
      - input:
          bind <-> name
      - label "Email:"
      - input:
          bind <-> email
      - label "Password:"
      - password:
          bind <-> password
```

### Tab

Creates a tabbed interface:

```yaml
- tab:
    children:
      - tab "General":
          children:
            - label "General Settings"
            - checkbox "Enable feature":
                bind <-> settings.enableFeature
      - tab "Advanced":
          children:
            - label "Advanced Settings"
            - input:
                bind <-> settings.apiKey
```

### Pane

Creates a split pane with an adjustable divider:

```yaml
- pane horizontal:
    dividerPosition: 0.3  # 30% for first panel
    children:
      - tree:              # Left panel
          data: "{fileTree}"
      - textarea:          # Right panel
          bind <-> fileContent
```

### Scroll

Creates a scrollable container:

```yaml
- scroll:
    children:
      - column:
          children:
            # Lots of content here...
```

### Group

Visual grouping with optional title:

```yaml
- group "User Information":
    children:
      - label "Name: {user.name}"
      - label "Email: {user.email}"
```

## UI Widgets

YAML-UI supports a standard set of widgets found in most UI toolkits:

### Label

Displays static text:

```yaml
- label "Hello World":
    font: $fonts.title
    color: $colors.primary
```

### Button

Clickable control:

```yaml
- button "Save":
    on_click: saveData/0
    enabled: "{isFormValid}"
    theme: "button.primary"
```

### Input

Text entry field:

```yaml
- input:
    bind <-> username
    placeholder: "Enter username"
    size: 200x40
```

### Checkbox

Boolean toggle control:

```yaml
- checkbox "Remember me":
    bind <-> rememberLogin
```

### Radio

Exclusive selection from a group:

```yaml
- radio "Option 1":
    bind <-> selectedOption
    value: "option1"
- radio "Option 2":
    bind <-> selectedOption
    value: "option2"
```

### Select

Dropdown selection:

```yaml
- select:
    bind <-> country
    options:
      - value: "us"
        label: "United States"
      - value: "ca"
        label: "Canada"
      - value: "mx"
        label: "Mexico"
```

### Textarea

Multi-line text input:

```yaml
- textarea:
    bind <-> notes
    placeholder: "Enter notes here"
    size: 400x200
```

### Slider

Value selection along a range:

```yaml
- slider:
    bind <-> volume
    min: 0
    max: 100
    step: 1
```

### Progress

Progress indicator:

```yaml
- progress:
    value: "{loadingProgress}"
    max: 100
```

### Image

Image display:

```yaml
- image:
    source: "logo.png"
    size: 240x80
```

### Table

Tabular data display:

```yaml
- table:
    data: "{users}"
    columns:
      - field: "id"
        header: "ID"
        width: 60
      - field: "name"
        header: "Name"
        grow: 1
      - field: "email"
        header: "Email"
        width: 200
    on_select: selectUser/1
```

### Tree

Hierarchical data display:

```yaml
- tree:
    data: "{fileTree}"
    on_select: selectFile/1
```

### List

List of items:

```yaml
- list:
    data: "{items}"
    template: label "{item.name}"
    on_select: selectItem/1
```

## Data Binding

YAML-UI supports different binding directions:

```yaml
# Bidirectional (UI to state and state to UI)
bind <-> username

# One-way state to UI
bind -> displayName

# One-way UI to state
bind <- inputValue
```

String interpolation for dynamic content:

```yaml
- label "Hello, {username}!"
- button "Count: {counter}"
```

Conditional expressions:

```yaml
- button "Login":
    visible: "{!isLoggedIn}"
- label "Welcome back!":
    visible: "{isLoggedIn}"
```

 prefix:

```yaml
- button "Save":
    backgroundColor: $colors.primary
    color: $colors.text.primary
    padding: $padding.input
    borderRadius: $radius.md

- label "Welcome":
    font: $fonts.title
    color: $colors.primary

- row:
    spacing: $spacing.md
    padding: $padding.container
```

## Component Themes

Specific component variants can be applied using the `theme` property:

```yaml
- button "Save":
    theme: "button.primary"

- button "Cancel":
    theme: "button.text"

- button "Delete":
    theme: "button.danger"

- input:
    theme: "input.search"
```

## Theme Variables with State

You can use theme variables in conjunction with state variables:

```yaml
- button "Status":
    backgroundColor: "{isActive ? $colors.primary : $colors.secondary}"
    padding: $padding.input
```

## Runtime Theme Switching

Your application can support runtime theme switching by changing the imported theme. This is typically implemented in the code generator rather than the YAML-UI format itself.

## Intended Usage

The theme system is designed for several scenarios:

### 1. Brand Consistency

Teams can encode brand guidelines into theme files, ensuring consistency across all UI elements. This is particularly useful for:
- Corporate applications that need to follow brand guidelines
- White-label products that need different themes for different clients
- Products with multiple sub-brands

### 2. Light/Dark Mode

Create light and dark themes that inherit from a base theme:

```yaml
# light_theme.yui
import_theme: "base_theme.yui"

theme:
  colors:
    background:
      primary: "#FFFFFF"
    text:
      primary: "#202124"

# dark_theme.yui
import_theme: "base_theme.yui"

theme:
  colors:
    background:
      primary: "#202124"
    text:
      primary: "#FFFFFF"
```

### 3. Platform-Specific Adaptations

Theme variants can adapt to different platforms while maintaining core design language:

```yaml
# android_theme.yui
import_theme: "base_theme.yui"

theme:
  radius:
    md: 8  # More rounded corners for Android
  
  fonts:
    body: "Roboto 16"

# ios_theme.yui
import_theme: "base_theme.yui"

theme:
  radius:
    md: 6  # iOS-style rounded corners
  
  fonts:
    body: "San Francisco 16"
```

### 4. Design System Implementation

Themes provide a way to implement design systems with tokens for:
- Color
- Typography
- Spacing
- Sizing
- Shape (border radius, etc.)
- Component variants

This systematic approach makes it easier to maintain design consistency as applications grow.

## Actions

Actions link UI events to application logic:

```yaml
actions:
  - increment/0       # Takes no parameters
  - updateUser/1      # Takes one parameter
  - saveData/0        # Takes no parameters
```

Event handling:

```yaml
- button "Save":
    on_click: saveData/0

- input:
    on_change: updateInput/1
```

## Complete Example

```yaml
app: "Task Manager"
import_theme: "base_theme.yui"

state:
  tasks: []
  newTaskTitle: ""
  selectedTaskIndex: -1

view:
  - column:
      padding: 16px
      spacing: $spacing.md
      children:
        - label "Task Manager":
            font: $fonts.title
            color: $colors.primary
        
        - row:
            spacing: 8
            children:
              - input:
                  bind <-> newTaskTitle
                  placeholder: "New task title"
                  size: 300x40
              
              - button "Add":
                  on_click: addTask/0
                  enabled: "{newTaskTitle != ''}"
                  theme: "button.primary"
        
        - list:
            data: "{tasks}"
            template: checkbox "{item.title}":
              bind <-> "tasks[{index}].completed"
            on_select: selectTask/1
            grow: 1
        
        - row:
            justify: end
            spacing: 8
            children:
              - button "Delete":
                  on_click: deleteTask/0
                  enabled: "{selectedTaskIndex >= 0}"
                  theme: "button.danger"
              - button "Clear Completed":
                  on_click: clearCompleted/0

actions:
  - addTask/0
  - selectTask/1
  - deleteTask/0
  - clearCompleted/0
```

## Full Widget Reference

### Core Containers

| Widget | Description |
|--------|-------------|
| `row` | Horizontal layout container |
| `column` | Vertical layout container |
| `grid` | Grid-based layout with rows and columns |
| `pane` | Splitpane with adjustable divider |
| `tab` | Tabbed container with multiple pages |
| `scroll` | Scrollable container |
| `group` | Visual grouping with optional border/title |
| `frame` | Container with border/title |
| `box` | Generic container (can be styled as various visual boxes) |
| `stack` | Stacked layers with only one visible at a time |
| `viewport` | Scrollable viewport with content larger than visible area |

### Basic Widgets

| Widget | Description |
|--------|-------------|
| `label` | Static text display |
| `button` | Clickable control |
| `checkbox` | Boolean toggle control |
| `radio` | Exclusive selection control |
| `input` | Text entry field |
| `password` | Password entry field |
| `textarea` | Multi-line text input |
| `select` | Dropdown selection control |
| `slider` | Value selection along a range |
| `progress` | Progress indicator/bar |
| `spinner` | Numeric input with up/down buttons |
| `image` | Image display (basic image formats) |
| `switch` | On/off toggle switch |
| `link` | Hyperlink-style clickable text |
| `icon` | Icon display with optional action |
| `divider` | Horizontal or vertical separator line |
| `spacer` | Fixed or flexible empty space |

### Advanced Input Widgets

| Widget | Description |
|--------|-------------|
| `date` | Date picker control |
| `time` | Time picker control |
| `color` | Color selection control |
| `file` | File selection control |
| `combo` | Combination dropdown/editable field |
| `autocomplete` | Text input with completion suggestions |
| `search` | Search input with typical search features |
| `range` | Range selection with min/max values |

### Data Display Widgets

| Widget | Description |
|--------|-------------|
| `table` | Tabular data display |
| `tree` | Hierarchical data display |
| `list` | List of items (can be styled as listbox, dropdown, etc.) |
| `card` | Content container with consistent styling |
| `tooltip` | Contextual information popup |
| `badge` | Small numerical or status indicator |

### Containers and Navigation

| Widget | Description |
|--------|-------------|
| `toolbar` | Container for action buttons |
| `statusbar` | Status information display |
| `menubar` | Application menu container |
| `popup` | Popup/context menu |
| `dialog` | Modal or non-modal dialog window |
| `drawer` | Side panel that can appear/disappear |
| `expander` | Expandable/collapsible content section |

### Media and Basic Graphics

| Widget | Description |
|--------|-------------|
| `canvas` | Basic drawing surface |

## Layout Properties Reference

| Property | Description | Values | Example |
|----------|-------------|--------|---------|
| `align` | Cross-axis alignment | `start`, `center`, `end`, `stretch` | `align: center` |
| `justify` | Main-axis alignment | `start`, `center`, `end`, `spaceBetween`, `spaceAround`, `spaceEvenly` | `justify: spaceBetween` |
| `grow` | Whether element expands to fill space | `boolean` or number (flex factor) | `grow: 1` |
| `shrink` | Whether element can shrink | `boolean` or number | `shrink: true` |
| `wrap` | Whether children wrap to next line | `boolean` | `wrap: true` |
| `spacing` | Space between children | Size value or [h, v] | `spacing: 8` or `spacing: [16, 8]` |
| `padding` | Space inside element | Size value, CSS-like string, or object | `padding: 16px` or `padding: {top: 8, left: 16}` |
| `margin` | Space around element | Size value, CSS-like string, or object | `margin: 8px 16px` |
| `width` | Element width | Size value or `fill` | `width: 240px` or `width: fill` |
| `height` | Element height | Size value or `fill` | `height: 40px` |
| `size` | Width and height combined | WxH format | `size: 120x40` |
| `visible` | Whether element is shown | `boolean` or expression | `visible: "{isLoggedIn}"` |
| `enabled` | Whether element is interactive | `boolean` or expression | `enabled: true` |

## Code Generation

The YAML-UI format can be used to generate native UI code for different platforms:

1. **Flutter**: Mobile and desktop applications
2. **OwlKettle**: Native GTK applications in Nim
3. **HTML/CSS/JS**: Web applications
4. **SwiftUI**: iOS/macOS applications
5. **WPF/XAML**: Windows applications

## Conclusion

YAML-UI provides a clean, readable, and portable way to define user interfaces that can be used across multiple platforms. By separating the UI description from implementation details, it allows for greater code reuse and consistency across different environments.