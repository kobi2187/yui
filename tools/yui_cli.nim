import os, strutils, strformat
import ../src/yui_validator
import ../src/generators/yui_flutter_generator
import ../src/generators/yui_owlkettle_generator
import ../src/generators/yui_wxnim_generator
import ../src/tools/yui_html_visualizer

proc printUsage() =
  echo """
YAML-UI Command Line Interface

Usage:
  yui <command> [options] <file.yui> [output]

Commands:
  validate <file.yui>                    - Validate a YUI file
  generate <target> <file.yui> [output]  - Generate code for target platform
  preview <file.yui> [port]              - Start live preview server
  help                                   - Show this help message

Targets:
  flutter     - Generate Flutter/Dart code
  owlkettle   - Generate OwlKettle/Nim code
  wxnim       - Generate wxNim code

Examples:
  yui validate app.yui
  yui generate flutter app.yui main.dart
  yui generate owlkettle app.yui main.nim
  yui generate wxnim app.yui main.nim
  yui preview app.yui 8080
"""

proc validateCommand(filename: string) =
  if not fileExists(filename):
    echo "Error: File not found: ", filename
    quit(1)
  
  echo "Validating ", filename
  let result = yui_validator.loadAndValidateYuiFile(filename)
  
  if result.errors.len > 0:
    echo "Validation errors:"
    for error in result.errors:
      echo "  - ", error
    quit(1)
  else:
    echo "✓ File is valid!"
    
    # Print summary
    echo "\nApplication: ", result.app.app
    
    if result.app.importTheme.isSome:
      echo "Imports theme: ", result.app.importTheme.get
    
    if result.app.state.isSome:
      echo "State variables: ", result.app.state.get.len
    
    echo "UI Elements: ", result.app.view.len
    
    if result.app.actions.isSome:
      echo "Actions: ", result.app.actions.get.len

proc generateCommand(target: string, filename: string, output: string = "") =
  if not fileExists(filename):
    echo "Error: File not found: ", filename
    quit(1)
  
  # First validate
  echo "Validating ", filename
  let validation = yui_validator.loadAndValidateYuiFile(filename)
  if validation.errors.len > 0:
    echo "Validation errors:"
    for error in validation.errors:
      echo "  - ", error
    quit(1)
  
  # Generate code
  echo "Generating ", target, " code from ", filename
  
  var generatedCode = ""
  var defaultExtension = ""
  
  case target.toLowerAscii():
  of "flutter":
    generatedCode = yui_flutter_generator.generateFlutterFromYuiFile(filename)
    defaultExtension = ".dart"
  of "owlkettle":
    generatedCode = yui_owlkettle_generator.generateOwlKettleFromYuiFile(filename)
    defaultExtension = ".nim"
  of "wxnim":
    generatedCode = yui_wxnim_generator.generateWxNimFromYuiFile(filename)
    defaultExtension = ".nim"
  else:
    echo "Error: Unknown target '", target, "'"
    echo "Available targets: flutter, owlkettle, wxnim"
    quit(1)
  
  # Determine output file
  let outputFile = if output != "": 
                     output 
                   else: 
                     filename.changeFileExt(defaultExtension)
  
  # Write output
  try:
    writeFile(outputFile, generatedCode)
    echo "✓ Code generated successfully: ", outputFile
    
    # Show compilation instructions
    case target.toLowerAscii():
    of "flutter":
      echo "To run: flutter run -t ", outputFile
    of "owlkettle", "wxnim":
      echo "To compile: nim c -r ", outputFile
    
  except IOError as e:
    echo "Error writing file: ", e.msg
    quit(1)

proc previewCommand(filename: string, port: int = 5000) =
  if not fileExists(filename):
    echo "Error: File not found: ", filename
    quit(1)
  
  echo "Starting preview server for ", filename
  echo "Open http://localhost:", port, " in your browser"
  echo "Press Ctrl+C to stop"
  
  # Start the HTML visualizer
  yui_html_visualizer.startPreviewServer(port, autoWatch = true)

proc main() =
  let args = commandLineParams()
  
  if args.len == 0:
    printUsage()
    quit(1)
  
  let command = args[0].toLowerAscii()
  
  case command:
  of "help", "-h", "--help":
    printUsage()
  
  of "validate":
    if args.len < 2:
      echo "Error: Missing filename"
      echo "Usage: yui validate <file.yui>"
      quit(1)
    validateCommand(args[1])
  
  of "generate":
    if args.len < 3:
      echo "Error: Missing target or filename"
      echo "Usage: yui generate <target> <file.yui> [output]"
      quit(1)
    
    let target = args[1]
    let filename = args[2]
    let output = if args.len > 3: args[3] else: ""
    
    generateCommand(target, filename, output)
  
  of "preview":
    if args.len < 2:
      echo "Error: Missing filename"
      echo "Usage: yui preview <file.yui> [port]"
      quit(1)
    
    let filename = args[1]
    let port = if args.len > 2: 
                 try: parseInt(args[2])
                 except: 5000
               else: 5000
    
    previewCommand(filename, port)
  
  else:
    echo "Error: Unknown command '", command, "'"
    printUsage()
    quit(1)

when isMainModule:
  main()