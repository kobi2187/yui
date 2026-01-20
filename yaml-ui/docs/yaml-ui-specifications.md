# YAML-UI Comprehensive Reference Example

This document contains a complete reference implementation of a YAML-UI file that showcases all available options and components.

```yaml
# app-reference.yui - Comprehensive YAML-UI reference example
app: "YAML-UI Reference Application"
import_theme: "base_theme.yui"  # Import base theme

# State variables with default values
state:
  # Basic types
  username: ""          # String
  age: 25               # Number
  isLoggedIn: false     # Boolean
  selectedOptions: []   # Array
  userProfile: {}       # Object
  
  # Complex state example
  items:
    - id: 1
      name: "Item One"
      price: 19.99
    - id: 2
      name: "Item Two"
      price: 29.99

# UI structure
view:
  # App container
  - column:
      padding: $padding.container
      spacing: $spacing.lg
      align: stretch      # stretch children to fill width
      
      children:
        # Header section
        - row:
            padding: $padding.header
            justify: spaceBetween  # space elements evenly
            align: center          # center vertically
            
            children:
              - label "YAML-UI Demo":
                  font: $fonts.header
                  color: $colors.primary
              
              - button 120x40 "Login":
                  on_click: login/1
                  visible: "{!isLoggedIn}"  # Conditional visibility
                  theme: "button.primary"
              
              - button "Logout":
                  on_click: logout/0
                  visible: "{isLoggedIn}"
                  theme: "button.secondary"
        
        # Main content area
        - row:
            spacing: $spacing.md
            grow: 1           # Take available space
            
            children:
              # Sidebar
              - column 240px:
                  padding: $padding.panel
                  spacing: $spacing.sm
                  background: $colors.background.secondary
                  
                  children:
                    - label "Navigation":
                        font: $fonts.sectionHeader
                    
                    # Navigation items
                    - button "Dashboard":
                        on_click: navigate/1
                        width: fill     # Fill container width
                        align: left     # Left-align text
                    
                    - button "Profile":
                        on_click: navigate/1
                        width: fill
                        align: left
                    
                    - button "Settings":
                        on_click: navigate/1
                        width: fill
                        align: left
              
              # Main panel
              - column:
                  padding: $padding.panel
                  spacing: $spacing.md
                  grow: 1       # Take remaining space
                  
                  children:
                    - label "User Profile":
                        font: $fonts.sectionHeader
                    
                    # Form section
                    - grid 2x3:
                        spacing: [16, 8]  # [horizontal, vertical]
                        
                        children:
                          # Row 1
                          - label "Username:":
                              align: right
                          
                          - input:
                              bind <-> username
                              placeholder: "Enter username"
                              width: fill
                          
                          # Row 2
                          - label "Age:":
                              align: right
                          
                          - input:
                              bind <-> age
                              type: number
                              min: 0
                              max: 120
                          
                          # Row 3
                          - label "Options:":
                              align: right
                          
                          - select:
                              bind <-> selectedOptions
                              multiple: true
                              options:
                                - value: "option1"
                                  label: "Option 1"
                                - value: "option2"
                                  label: "Option 2"
                                - value: "option3"
                                  label: "Option 3"
                    
                    # Checkboxes
                    - checkbox "Remember me":
                        bind <-> isLoggedIn
                    
                    # Data display section
                    - label "Items":
                        font: $fonts.sectionHeader
                    
                    # Table/List view
                    - table:
                        data: "{items}"
                        columns:
                          - field: "id"
                            header: "ID"
                            width: 60
                          - field: "name"
                            header: "Item Name"
                            grow: 1
                          - field: "price"
                            header: "Price"
                            width: 100
                            format: "currency"
                        on_select: selectItem/1
                    
                    # Button row
                    - row:
                        justify: end
                        spacing: $spacing.sm
                        
                        children:
                          - button "Cancel":
                              theme: "button.text"
                              on_click: cancel/0
                          
                          - button "Save":
                              theme: "button.primary"
                              on_click: save/1

# List of required action handlers
actions:
  - login/1        # Takes 1 parameter (state)
  - logout/0       # Takes 0 parameters
  - navigate/1     # Takes 1 parameter (route)
  - selectItem/1   # Takes 1 parameter (item)
  - cancel/0       # Takes 0 parameters
  - save/1         # Takes 1 parameter (state)
```

## Theme Definition (base_theme.yui)

```yaml
# base_theme.yui
theme:
  # Typography
  fonts:
    header: "Roboto 24 bold"
    sectionHeader: "Roboto 18 medium"
    body: "Roboto 16"
    small: "Roboto 14"
  
  # Color palette
  colors:
    primary: "#4285F4"
    secondary: "#34A853"
    danger: "#EA4335"
    warning: "#FBBC05"
    
    text:
      primary: "#202124"
      secondary: "#5F6368"
      disabled: "#9AA0A6"
    
    background:
      primary: "#FFFFFF"
      secondary: "#F1F3F4"
      tertiary: "#E8EAED"
  
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
      default: 240x40
      small: 120x32
      large: 360x48
  
  # Spacing
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
    header: 16px 24px
    input: 8px 12px
  
  # Component-specific styles
  button:
    base:
      borderRadius: 4
      fontWeight: 500
      transition: "all 0.2s ease"
    
    primary:
      extends: "button.base"
      backgroundColor: $colors.primary
      color: "#FFFFFF"
    
    secondary:
      extends: "button.base"
      backgroundColor: $colors.secondary
      color: "#FFFFFF"
    
    danger:
      extends: "button.base"
      backgroundColor: $colors.danger
      color: "#FFFFFF"
    
    text:
      extends: "button.base"
      backgroundColor: "transparent"
      color: $colors.primary
  
  input:
    base:
      borderRadius: 4
      borderColor: "#CCCCCC"
      padding: $padding.input
    
    search:
      extends: "input.base"
      iconLeft: "search"
      backgroundColor: $colors.background.secondary
```

## Layout Property Reference

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

## State Binding Reference

| Syntax | Description | Example |
|--------|-------------|---------|
| `bind <-> prop` | Bidirectional binding | `bind <-> username` |
| `bind -> prop` | Model to view (one-way) | `bind -> displayName` |
| `bind <- prop` | View to model (one-way) | `bind <- inputValue` |
| `{expression}` | Expression binding (read-only) | `text: "Hello, {username}"` |

## Event Handling Reference

| Event | Description | Example |
|-------|-------------|---------|
| `on_click` | Mouse/touch click | `on_click: handleClick/1` |
| `on_change` | Value changed | `on_change: updateValue/2` |
| `on_focus` | Element received focus | `on_focus: highlightField/1` |
| `on_blur` | Element lost focus | `on_blur: validateField/1` |
| `on_submit` | Form submission | `on_submit: submitForm/1` |
| `on_select` | Item selection | `on_select: selectItem/1` |

These references provide a complete overview of the YAML-UI format capabilities for both documentation and testing purposes.