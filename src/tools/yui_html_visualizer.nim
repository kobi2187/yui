import jester, asyncdispatch, os
import tables, options, strutils, strformat, sequtils
import yaml
import yui_validator

# Enhanced HTML renderer for YUI
proc renderYuiToHtml*(yui: string): string =
  let app = yui_validator.parseYuiApp(yui)
  var html = """
  <!DOCTYPE html>
  <html>
  <head>
    <title>YUI Preview: """ & app.app & """</title>
    <style>
      body { font-family: system-ui, sans-serif; padding: 20px; }
      
      /* Core layout styles */
      .row { 
        display: flex; 
        flex-direction: row; 
      }
      .column { 
        display: flex; 
        flex-direction: column; 
      }
      
      /* Alignment classes */
      .align-start { align-items: flex-start; }
      .align-center { align-items: center; }
      .align-end { align-items: flex-end; }
      .align-stretch { align-items: stretch; }
      
      /* Justification classes */
      .justify-start { justify-content: flex-start; }
      .justify-center { justify-content: center; }
      .justify-end { justify-content: flex-end; }
      .justify-space-between { justify-content: space-between; }
      .justify-space-around { justify-content: space-around; }
      .justify-space-evenly { justify-content: space-evenly; }
      
      /* Grow and shrink */
      .grow-1 { flex-grow: 1; }
      .grow-0 { flex-grow: 0; }
      .shrink-1 { flex-shrink: 1; }
      .shrink-0 { flex-shrink: 0; }
      
      /* Element styles */
      .label { margin: 4px 0; }
      .button { 
        background: #4285F4; 
        color: white; 
        border: none; 
        padding: 8px 16px; 
        border-radius: 4px;
        cursor: pointer;
      }
      .input { padding: 8px; border-radius: 4px; border: 1px solid #ccc; }
      .checkbox { margin: 8px 0; }
      
      /* Visualization helpers */
      .grid {
        display: grid;
        border: 1px dashed #ccc;
      }
      .grid-cell {
        border: 1px dotted #aaa;
        padding: 4px;
      }
      
      /* Developer debug info */
      .debug-info {
        position: absolute;
        background: rgba(0,0,0,0.7);
        color: white;
        padding: 4px;
        font-size: 10px;
        display: none;
      }
      *:hover > .debug-info {
        display: block;
      }
    </style>
  </head>
  <body>
  """

  # Function to recursively render elements with all layout options
  proc renderElement(element: Element, indent: int = 0): string =
    let indentStr = "  ".repeat(indent)
    var result = ""
    var classes: seq[string] = @[]
    var styles: seq[string] = @[]
    
    # Debug information to show on hover
    let elementInfo = &"{element.elementType}"
    
    # Process common layout properties
    if element.properties.align.isSome:
      classes.add("align-" & $element.properties.align.get)
    
    if element.properties.justify.isSome:
      classes.add("justify-" & $element.properties.justify.get)
    
    if element.properties.grow.isSome:
      if element.properties.grow.get > 0:
        classes.add("grow-1")
        styles.add(&"flex-grow: {element.properties.grow.get}")
      else:
        classes.add("grow-0")
    
    if element.properties.shrink.isSome:
      if element.properties.shrink.get:
        classes.add("shrink-1")
      else:
        classes.add("shrink-0")
    
    # Handle padding
    if element.properties.padding.isSome:
      styles.add("padding: " & element.properties.padding.get)
    
    # Handle margin
    if element.properties.margin.isSome:
      styles.add("margin: " & element.properties.margin.get)
    
    # Handle width & height
    if element.properties.width.isSome:
      styles.add("width: " & element.properties.width.get)
    
    if element.properties.height.isSome:
      styles.add("height: " & element.properties.height.get)
    
    # Handle dimensions (WxH)
    if element.dimensions.isSome:
      let dims = element.dimensions.get.split('x')
      if dims.len >= 1 and dims[0].len > 0:
        styles.add("width: " & dims[0] & "px")
      if dims.len >= 2 and dims[1].len > 0:
        styles.add("height: " & dims[1] & "px")
    
    # Process specific element types
    case element.elementType
    of "label":
      classes.add("label")
      result.add(indentStr & "<div class=\"" & classes.join(" ") & "\"")
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      
      if element.content.isSome:
        # Process interpolations like {counter}
        var content = element.content.get
        content = content.replace("{", "<span style=\"color: #4285F4\">{")
        content = content.replace("}", "}</span>")
        result.add(indentStr & "  " & content & "\n")
      
      result.add(indentStr & "</div>\n")
    
    of "button":
      classes.add("button")
      result.add(indentStr & "<button class=\"" & classes.join(" ") & "\"")
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      
      # Handle theme
      if element.properties.theme.isSome:
        let theme = element.properties.theme.get
        if theme == "button.danger":
          result.add(" style=\"background-color: #EA4335" & 
                   (if styles.len > 0: "; " & styles.join("; ") else: "") & "\"")
      
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      
      if element.content.isSome:
        result.add(indentStr & "  " & element.content.get & "\n")
      
      result.add(indentStr & "</button>\n")
    
    of "input":
      classes.add("input")
      result.add(indentStr & "<div style=\"position: relative;\">\n")
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo)
      
      # Show binding info
      if element.properties.bind.isSome:
        result.add(" → bind " & $element.properties.bind.get.direction & 
                 " " & element.properties.bind.get.property)
      
      result.add("</div>\n")
      result.add(indentStr & "  <input class=\"" & classes.join(" ") & "\"")
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      
      if element.rawProperties.hasKey("placeholder"):
        result.add(" placeholder=\"" & element.rawProperties["placeholder"].content & "\"")
      
      result.add("/>\n")
      result.add(indentStr & "</div>\n")
    
    of "checkbox":
      classes.add("checkbox")
      result.add(indentStr & "<div class=\"" & classes.join(" ") & "\"")
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo)
      
      # Show binding info
      if element.properties.bind.isSome:
        result.add(" → bind " & $element.properties.bind.get.direction & 
                 " " & element.properties.bind.get.property)
      
      result.add("</div>\n")
      
      result.add(indentStr & "  <input type=\"checkbox\"/>")
      if element.content.isSome:
        result.add(" <span>" & element.content.get & "</span>")
      result.add("\n")
      
      result.add(indentStr & "</div>\n")
    
    of "row":
      classes.add("row")
      result.add(indentStr & "<div class=\"" & classes.join(" ") & "\"")
      
      # Add spacing as gap
      if element.properties.spacing.isSome:
        styles.add("gap: " & element.properties.spacing.get & "px")
      
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      
      # Add children
      if element.children.isSome:
        for child in element.children.get:
          result.add(renderElement(child, indent + 2))
      
      result.add(indentStr & "</div>\n")
    
    of "column":
      classes.add("column")
      result.add(indentStr & "<div class=\"" & classes.join(" ") & "\"")
      
      # Add spacing as gap
      if element.properties.spacing.isSome:
        styles.add("gap: " & element.properties.spacing.get & "px")
      
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      
      # Add children
      if element.children.isSome:
        for child in element.children.get:
          result.add(renderElement(child, indent + 2))
      
      result.add(indentStr & "</div>\n")
    
    of "grid":
      classes.add("grid")
      result.add(indentStr & "<div class=\"" & classes.join(" ") & "\"")
      
      # Set grid template columns based on dimensions
      var columns = 2  # Default
      if element.dimensions.isSome:
        let parts = element.dimensions.get.split('x')
        if parts.len > 0 and parts[0].len > 0:
          try:
            columns = parseInt(parts[0])
          except:
            discard
      
      styles.add("grid-template-columns: repeat(" & $columns & ", 1fr)")
      
      # Add spacing as gap
      if element.properties.spacing.isSome:
        let spacing = element.properties.spacing.get
        if spacing.startsWith("[") and spacing.endsWith("]"):
          let parts = spacing[1..^2].split(',')
          if parts.len >= 2:
            styles.add("column-gap: " & parts[0].strip() & "px")
            styles.add("row-gap: " & parts[1].strip() & "px")
        else:
          styles.add("gap: " & spacing & "px")
      
      if styles.len > 0:
        result.add(" style=\"" & styles.join("; ") & "\"")
      
      result.add(">\n")
      
      # Add debug info
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      
      # Add children as grid cells
      if element.children.isSome:
        for child in element.children.get:
          result.add(indentStr & "  <div class=\"grid-cell\">\n")
          result.add(renderElement(child, indent + 4))
          result.add(indentStr & "  </div>\n")
      
      result.add(indentStr & "</div>\n")
    
    of "table":
      result.add(indentStr & "<div style=\"position: relative;\">\n")
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      result.add(indentStr & "  <table style=\"border-collapse: collapse; width: 100%;\">\n")
      
      # Handle columns
      if element.rawProperties.hasKey("columns") and element.rawProperties["columns"].kind == ySequence:
        result.add(indentStr & "    <thead>\n")
        result.add(indentStr & "      <tr>\n")
        
        for colNode in element.rawProperties["columns"]:
          if colNode.kind == yMapping:
            var headerText = "Column"
            
            for pair in colNode.pairs:
              if pair[0].content == "header":
                headerText = pair[1].content
                break
            
            result.add(indentStr & "        <th style=\"border: 1px solid #ddd; padding: 8px; text-align: left;\">" & 
                      headerText & "</th>\n")
        
        result.add(indentStr & "      </tr>\n")
        result.add(indentStr & "    </thead>\n")
      
      # Show placeholder for data
      if element.rawProperties.hasKey("data"):
        let dataSource = element.rawProperties["data"].content
        result.add(indentStr & "    <tbody>\n")
        result.add(indentStr & "      <tr>\n")
        result.add(indentStr & "        <td colspan=\"5\" style=\"border: 1px solid #ddd; padding: 8px;\">\n")
        result.add(indentStr & "          Data bound to: " & dataSource & "\n")
        result.add(indentStr & "        </td>\n")
        result.add(indentStr & "      </tr>\n")
        result.add(indentStr & "    </tbody>\n")
      
      result.add(indentStr & "  </table>\n")
      result.add(indentStr & "</div>\n")
    
    else:
      # Default for unsupported elements
      result.add(indentStr & "<div style=\"border: 1px dashed red; padding: 8px; position: relative;\">\n")
      result.add(indentStr & "  <div class=\"debug-info\">" & elementInfo & "</div>\n")
      result.add(indentStr & "  Unsupported element: " & element.elementType & "\n")
      result.add(indentStr & "</div>\n")
    
    return result

  # Render the main view
  if app.view.len > 0:
    html.add(renderElement(app.view[0]))
  else:
    html.add("<div>No UI elements defined</div>")
  
  # Add controls for debugging and visualization
  html.add("""
  <div style="position: fixed; bottom: 10px; right: 10px; background: #f5f5f5; padding: 10px; border-radius: 4px; border: 1px solid #ddd;">
    <label><input type="checkbox" id="toggle-debug" checked> Show Debug Info</label><br>
    <label><input type="checkbox" id="toggle-borders"> Show Layout Borders</label>
  </div>
  <script>
    document.getElementById('toggle-debug').addEventListener('change', function() {
      document.querySelectorAll('.debug-info').forEach(el => {
        el.style.display = this.checked ? 'block' : 'none';
      });
    });
    
    document.getElementById('toggle-borders').addEventListener('change', function() {
      if (this.checked) {
        document.querySelectorAll('.row, .column').forEach(el => {
          el.style.border = '1px dashed #aaa';
        });
      } else {
        document.querySelectorAll('.row, .column').forEach(el => {
          el.style.border = 'none';
        });
      }
    });
  </script>
  """)
  
  html.add("</body></html>")
  return html

# Simple file watcher function to detect changes in YUI files
proc watchFile(filename: string, callback: proc()) =
  var lastModTime = getLastModificationTime(filename)
  
  while true:
    sleep(500)  # Check every 500ms
    let currentModTime = getLastModificationTime(filename)
    if currentModTime != lastModTime:
      lastModTime = currentModTime
      callback()

# Web server for the live preview
proc startPreviewServer*(port: int = 5000, autoWatch: bool = true) =
  # Setup Jester routes
  settings:
    port = Port(port)
  
  var watchedFile = ""
  var fileContent = ""
  
  routes:
    get "/":
      resp """
      <html>
      <head>
        <title>YUI Live Preview</title>
        <style>
          body { 
            display: flex; 
            flex-direction: column;
            height: 100vh; 
            margin: 0; 
            font-family: system-ui, sans-serif;
          }
          
          header {
            background: #4285F4;
            color: white;
            padding: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
          
          .content {
            display: flex;
            flex: 1;
            overflow: hidden;
          }
          
          #editor, #preview { 
            flex: 1; 
            overflow: auto; 
            position: relative;
          }
          
          #editor { 
            border-right: 1px solid #ccc;
          }
          
          #editor textarea { 
            width: 100%; 
            height: calc(100% - 40px); 
            padding: 10px;
            font-family: monospace; 
            font-size: 14px;
            border: none;
            resize: none;
          }
          
          #preview iframe { 
            width: 100%; 
            height: 100%; 
            border: none; 
          }
          
          .controls {
            padding: 8px;
            background: #f5f5f5;
            border-bottom: 1px solid #ddd;
          }
          
          button {
            background: #4285F4;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
          }
          
          button:hover {
            background: #2a75f3;
          }
          
          .file-info {
            font-size: 12px;
            color: #666;
            margin-left: 10px;
          }
        </style>
      </head>
      <body>
        <header>
          <h1>YAML-UI Live Preview</h1>
          <div>
            <button onclick="openFile()">Open YUI File</button>
            <input type="file" id="file-input" style="display: none;" accept=".yui,.yaml,.yml">
            <span class="file-info" id="file-info"></span>
          </div>
        </header>
        
        <div class="content">
          <div id="editor">
            <div class="controls">
              <button onclick="updatePreview()">Update Preview</button>
              <button onclick="saveToFile()">Save</button>
            </div>
            <textarea id="yui-code">app: "YUI Preview"

state:
  counter: 0

view:
  - column:
      spacing: 16
      padding: 16px
      children:
        - label "YUI Live Preview":
            font: "24 bold"
        - label "Edit the YUI code on the left to see changes"
        - button "Click Me"
</textarea>
          </div>
          <div id="preview">
            <iframe id="preview-frame" src="/preview"></iframe>
          </div>
        </div>
        
        <script>
          let currentFilename = null;
          
          function updatePreview() {
            const yuiCode = document.getElementById('yui-code').value;
            fetch('/preview', {
              method: 'POST',
              body: yuiCode
            })
            .then(response => response.text())
            .then(html => {
              const frame = document.getElementById('preview-frame');
              frame.contentWindow.document.open();
              frame.contentWindow.document.write(html);
              frame.contentWindow.document.close();
            });
          }
          
          function openFile() {
            document.getElementById('file-input').click();
          }
          
          document.getElementById('file-input').addEventListener('change', function(e) {
            const file = e.target.files[0];
            if (file) {
              currentFilename = file.name;
              document.getElementById('file-info').textContent = 'File: ' + file.name;
              
              const reader = new FileReader();
              reader.onload = function(e) {
                document.getElementById('yui-code').value = e.target.result;
                updatePreview();
                
                // Tell the server we're watching this file
                fetch('/watch', {
                  method: 'POST',
                  body: file.path || file.name
                });
              };
              reader.readAsText(file);
            }
          });
          
          function saveToFile() {
            const yuiCode = document.getElementById('yui-code').value;
            if (!yuiCode) return;
            
            const filename = currentFilename || 'preview.yui';
            const blob = new Blob([yuiCode], {type: 'text/plain'});
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
          }
          
          // Check for file changes every 2 seconds if watching a file
          setInterval(function() {
            if (currentFilename) {
              fetch('/check')
                .then(response => response.text())
                .then(text => {
                  if (text !== document.getElementById('yui-code').value) {
                    // File changed externally
                    document.getElementById('yui-code').value = text;
                    updatePreview();
                  }
                });
            }
          }, 2000);
          
          // Update on load
          updatePreview();
        </script>
      </body>
      </html>
      """
    
    get "/preview":
      let defaultYui = """
      app: "YUI Preview"
      
      view:
        - label "YUI Live Preview"
      """
      resp renderYuiToHtml(defaultYui)
    
    post "/preview":
      let yuiCode = request.body
      fileContent = yuiCode
      resp renderYuiToHtml(yuiCode)
    
    post "/watch":
      let filename = request.body
      echo "Watching file: ", filename
      watchedFile = filename
      
      if autoWatch and fileExists(watchedFile):
        fileContent = readFile(watchedFile)
        # Start the file watcher in a separate thread
        spawn proc() =
          watchFile(watchedFile, proc() =
            try:
              fileContent = readFile(watchedFile)
              echo "File changed: ", watchedFile
            except:
              echo "Error reading file: ", watchedFile
          )
      
      resp "OK"
    
    get "/check":
      if watchedFile != "" and fileExists(watchedFile):
        try:
          fileContent = readFile(watchedFile)
        except:
          echo "Error reading file: ", watchedFile
      
      resp fileContent

# Main function
when isMainModule:
  var port = 5000
  if paramCount() >= 1:
    try:
      port = parseInt(paramStr(1))
    except:
      echo "Invalid port number, using default: ", port
  
  echo "Starting YUI Preview server on http://localhost:", port
  startPreviewServer(port)