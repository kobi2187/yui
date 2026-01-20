import os, strutils, strformat, sequtils
import ../src/yui_validator
import ../src/generators/yui_flutter_generator
import ../src/generators/yui_owlkettle_generator
import ../src/generators/yui_wxnim_generator

type
  BuildTarget = enum
    Flutter = "flutter"
    OwlKettle = "owlkettle" 
    WxNim = "wxnim"
    All = "all"

  BuildResult = object
    filename: string
    target: string
    success: bool
    error: string
    outputFile: string

proc findYuiFiles(directory: string): seq[string] =
  result = @[]
  if not dirExists(directory):
    return
  
  for kind, path in walkDir(directory):
    if kind == pcFile and path.endsWith(".yui"):
      result.add(path)
    elif kind == pcDir:
      result.add(findYuiFiles(path))
  
  result = result.concat()

proc validateFile(filename: string): bool =
  let validation = yui_validator.loadAndValidateYuiFile(filename)
  if validation.errors.len > 0:
    echo "  ✗ Validation failed for ", filename
    for error in validation.errors:
      echo "    - ", error
    return false
  else:
    echo "  ✓ Validated ", filename
    return true

proc generateCode(filename: string, target: BuildTarget): BuildResult =
  result = BuildResult(filename: filename, target: $target, success: false)
  
  if not validateFile(filename):
    result.error = "Validation failed"
    return
  
  var generatedCode = ""
  var extension = ""
  
  try:
    case target:
    of Flutter:
      generatedCode = yui_flutter_generator.generateFlutterFromYuiFile(filename)
      extension = ".dart"
    of OwlKettle:
      generatedCode = yui_owlkettle_generator.generateOwlKettleFromYuiFile(filename)
      extension = ".nim"
    of WxNim:
      generatedCode = yui_wxnim_generator.generateWxNimFromYuiFile(filename)
      extension = ".nim"
    of All:
      result.error = "All target should not reach generateCode"
      return
    
    # Create output directory
    let outputDir = "output" / $target
    createDir(outputDir)
    
    # Generate output filename
    let baseName = filename.extractFilename().changeFileExt("")
    let outputFile = outputDir / (baseName & extension)
    
    # Write file
    writeFile(outputFile, generatedCode)
    
    result.success = true
    result.outputFile = outputFile
    echo "  ✓ Generated ", outputFile
    
  except Exception as e:
    result.error = e.msg
    echo "  ✗ Error generating ", $target, " for ", filename, ": ", e.msg

proc buildExamples(targets: seq[BuildTarget], pattern: string = "*.yui") =
  echo "Building YAML-UI examples..."
  echo "Targets: ", targets.mapIt($it).join(", ")
  echo ""
  
  # Find all YUI files
  let exampleDirs = @["examples/basic", "examples/advanced"]
  var yuiFiles: seq[string] = @[]
  
  for dir in exampleDirs:
    if dirExists(dir):
      yuiFiles.add(findYuiFiles(dir))
  
  if yuiFiles.len == 0:
    echo "No YUI files found in example directories"
    return
  
  echo "Found ", yuiFiles.len, " YUI files:"
  for file in yuiFiles:
    echo "  - ", file
  echo ""
  
  # Build results tracking
  var results: seq[BuildResult] = @[]
  var totalBuilds = 0
  var successfulBuilds = 0
  
  # Process each file
  for yuiFile in yuiFiles:
    echo "Processing ", yuiFile, ":"
    
    # Skip theme files (they're imported, not standalone apps)
    if yuiFile.contains("theme.yui"):
      echo "  - Skipping theme file"
      continue
    
    for target in targets:
      if target == All:
        # Build for all targets
        for t in [Flutter, OwlKettle, WxNim]:
          let result = generateCode(yuiFile, t)
          results.add(result)
          totalBuilds += 1
          if result.success:
            successfulBuilds += 1
      else:
        let result = generateCode(yuiFile, target)
        results.add(result)
        totalBuilds += 1
        if result.success:
          successfulBuilds += 1
    
    echo ""
  
  # Print summary
  echo "Build Summary:"
  echo "=" .repeat(50)
  echo &"Total builds: {totalBuilds}"
  echo &"Successful: {successfulBuilds}"
  echo &"Failed: {totalBuilds - successfulBuilds}"
  echo ""
  
  # Print detailed results
  if results.filterIt(not it.success).len > 0:
    echo "Failed builds:"
    for result in results.filterIt(not it.success):
      echo &"  ✗ {result.filename} -> {result.target}: {result.error}"
    echo ""
  
  if results.filterIt(it.success).len > 0:
    echo "Generated files:"
    for result in results.filterIt(it.success):
      echo &"  ✓ {result.outputFile}"

proc printUsage() =
  echo """
Build Examples Script

Usage:
  build_examples [target] [options]

Targets:
  flutter     - Build Flutter examples only
  owlkettle   - Build OwlKettle examples only
  wxnim       - Build wxNim examples only
  all         - Build for all targets (default)

Options:
  --clean     - Clean output directories before building
  --help      - Show this help message

Examples:
  build_examples                    # Build all targets
  build_examples flutter            # Build Flutter only
  build_examples all --clean        # Clean and build all
"""

proc cleanOutputDirs() =
  echo "Cleaning output directories..."
  let outputDirs = @["output/flutter", "output/owlkettle", "output/wxnim"]
  
  for dir in outputDirs:
    if dirExists(dir):
      try:
        removeDir(dir)
        echo "  ✓ Cleaned ", dir
      except:
        echo "  ✗ Failed to clean ", dir
    createDir(dir)

proc main() =
  let args = commandLineParams()
  var targets: seq[BuildTarget] = @[All]
  var shouldClean = false
  
  # Parse arguments
  for arg in args:
    case arg.toLowerAscii():
    of "flutter":
      targets = @[Flutter]
    of "owlkettle":
      targets = @[OwlKettle]
    of "wxnim":
      targets = @[WxNim]
    of "all":
      targets = @[All]
    of "--clean":
      shouldClean = true
    of "--help", "-h":
      printUsage()
      return
    else:
      echo "Unknown argument: ", arg
      printUsage()
      return
  
  # Clean if requested
  if shouldClean:
    cleanOutputDirs()
    echo ""
  
  # Ensure output directories exist
  createDir("output")
  createDir("output/flutter")
  createDir("output/owlkettle")
  createDir("output/wxnim")
  
  # Build examples
  buildExamples(targets)

when isMainModule:
  main()