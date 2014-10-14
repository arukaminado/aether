ranges = require './ranges'

# Problem Context (problemContext)
#
# Aether accepts a problemContext parameter via the constructor options or directly to createUserCodeProblem
# This context can be used to craft better errors messages.
#
# Example:
#   Incorrect user code is 'this.attack(Brak);'
#   Correct user code is 'this.attack("Brak");'
#   Error: 'Brak is undefined'
#   If we had a list of expected string references, we could provide a better error message:
#   'Brak is undefined. Are you missing quotes? Try this.attack("Brak");'
#
# Available Context Properties:
#   stringReferences: values that should be referred to as a string instead of a variable (e.g. "Brak", not Brak)
#   thisMethods: methods available on the 'this' object
#   thisProperties: properties available on the 'this' object
#   

module.exports.createUserCodeProblem = (options) ->
  options ?= {}
  options.aether ?= @  # Can either be called standalone or as an Aether method
  if options.type is 'transpile' and options.error
    extractTranspileErrorDetails options
  if options.type is 'runtime'
    extractRuntimeErrorDetails options

  reporter = options.reporter or 'unknown'  # Source of the problem, like 'jshint' or 'esprima' or 'aether'
  kind = options.kind or 'Unknown'  # Like 'W075' or 'InvalidLHSInAssignment'
  id = reporter + '_' + kind  # Uniquely identifies reporter + kind combination
  config = options.aether?.options?.problems?[id] or {}  # Default problem level/message/hint overrides

  p = isUserCodeProblem: true
  p.id = id
  p.level = config.level or options.level or 'error'  # 'error', 'warning', 'info'
  p.type = options.type or 'generic'  # Like 'runtime' or 'transpile', maybe later 'lint'
  p.message = config.message or options.message or "Unknown #{p.type} #{p.level}"  # Main error message (short phrase)
  p.hint = config.hint or options.hint or ''  # Additional details about error message (sentence)
  p.range = options.range  # Like [{ofs: 305, row: 15, col: 15}, {ofs: 312, row: 15, col: 22}], or null
  p.userInfo = options.userInfo ? {}  # Record extra information with the error here
  p


extractTranspileErrorDetails = (options) ->
  code = options.code or ''
  codePrefix = options.codePrefix or ''
  error = options.error
  options.message = error.message

  originalLines = code.slice(codePrefix.length).split '\n'
  lineOffset = codePrefix.split('\n').length - 1

  # TODO: move these into language-specific plugins
  switch options.reporter
    when 'jshint'
      options.message ?= error.reason
      options.kind ?= error.code
      unless options.level
        options.level = {E: 'error', W: 'warning', I: 'info'}[error.code[0]]
      line = error.line - codePrefix.split('\n').length
      if line >= 0
        if error.evidence?.length
          startCol = originalLines[line].indexOf error.evidence
          endCol = startCol + error.evidence.length
        else
          [startCol, endCol] = [0, originalLines[line].length - 1]
        # TODO: no way this works; what am I doing with code prefixes?
        options.range = [ranges.rowColToPos(line, startCol, code, codePrefix),
                         ranges.rowColToPos(line, endCol, code, codePrefix)]
      else
        # TODO: if we type an unmatched {, for example, then it thinks that line -2's function wrapped() { is unmatched...
        # TODO: no way this works; what am I doing with code prefixes?
        options.range = [ranges.offsetToPos(0, code, codePrefix),
                         ranges.offsetToPos(code.length - 1, code, codePrefix)]
    when 'esprima'
      # TODO: column range should extend to whole token. Mod Esprima, or extend to end of line?
      # TODO: no way this works; what am I doing with code prefixes?
      options.range = [ranges.rowColToPos(error.lineNumber - 1 - lineOffset, error.column - 1, code, codePrefix),
                       ranges.rowColToPos(error.lineNumber - 1 - lineOffset, error.column, code, codePrefix)]
    when 'acorn_loose'
      null
    when 'csredux'
      options.range = [ranges.rowColToPos(error.lineNumber - 1 - lineOffset, error.column - 1, code, codePrefix),
                       ranges.rowColToPos(error.lineNumber - 1 - lineOffset, error.column, code, codePrefix)]
    when 'aether'
      null
    when 'closer'
      if error.startOffset and error.endOffset
        range = ranges.offsetsToRange(error.startOffset, error.endOffset, code)
        options.range = [range.start, range.end]
    when 'lua2js'
      options.message ?= error.message
      rng = ranges.offsetsToRange(error.offset, error.offset, code, '')
      options.range = [rng.start, rng.end]
    when 'filbert'
      if error.loc
        columnOffset = 0
        columnOffset++ while originalLines[lineOffset - 2][columnOffset] is ' '
        # filbert lines are 1-based, columns are 0-based
        row = error.loc.line - lineOffset - 1
        col = error.loc.column - columnOffset
        start = ranges.rowColToPos(row, col, code, codePrefix)
        end = ranges.rowColToPos(row, col + error.raisedAt - error.pos, code, codePrefix)
        # Remove per-row indents
        start.ofs -= row * 4
        end.ofs -= row * 4
        options.range = [start, end]
    when 'iota'
      null
    else
      console.warn "Unhandled UserCodeProblem reporter", options.reporter

  options


extractRuntimeErrorDetails = (options) ->
  errorContext = options.problemContext or options.aether?.options?.problemContext
  languageID = options.aether?.options?.language
  if error = options.error
    options.kind ?= error.name  # I think this will pick up [Error, EvalError, RangeError, ReferenceError, SyntaxError, TypeError, URIError, DOMException]
    [options.message, options.hint] = explainErrorMessage error.message or error.toString(), error.hint, errorContext, languageID
    options.level ?= error.level
    options.userInfo ?= error.userInfo
  # NOTE: lastStatementRange set via instrumentation.logStatementStart(originalNode.originalRange)
  options.range ?= options.aether?.lastStatementRange
  if options.range
    lineNumber = options.range[0].row + 1
    if options.message.search(/^Line \d+/) != -1
      options.message = options.message.replace /^Line \d+/, (match, n) -> "Line #{lineNumber}"
    else
      options.message = "Line #{lineNumber}: #{options.message}"

module.exports.commonMethods = commonMethods = ['moveRight', 'moveLeft', 'moveUp', 'moveDown', 'attackNearbyEnemy', 'say', 'move', 'attackNearestEnemy', 'shootAt', 'rotateTo', 'shoot', 'distance', 'getNearestEnemy', 'getEnemies', 'attack', 'setAction', 'setTarget', 'getFriends', 'patrol']  # TODO: should be part of user configuration

explainErrorMessage = (msg, hint, context, languageID) ->
  if msg is "RangeError: Maximum call stack size exceeded"
    msg += ". (Did you use call a function recursively?)"

  if missingMethodMatch = msg.match /has no method '(.*?)'/
    method = missingMethodMatch[1]
    [closestMatch, closestMatchScore] = ['Murgatroyd Kerfluffle', 0]
    explained = false
    for commonMethod in commonMethods
      if method is commonMethod
        msg += ". (#{missingMethodMatch[1]} not available in this challenge.)"
        explained = true
        break
      else if method.toLowerCase() is commonMethod.toLowerCase()
        msg = "#{method} should be #{commonMethod} because JavaScript is case-sensitive."
        explained = true
        break
      else
        matchScore = string_score?.score commonMethod, method, 0.5
        if matchScore > closestMatchScore
          [closestMatch, closestMatchScore] = [commonMethod, matchScore]
    unless explained
      if closestMatchScore > 0.25
        msg += ". (Did you mean #{closestMatch}?)"
    msg = msg.replace 'TypeError:', 'Error:'
  
  else if missingReference = msg.match /ReferenceError: ([^\s]+) is not defined/
    # Use problemContext to update reference errors
    # TODO: thisValueAccess should come from the current Aether language
    thisValueAccess = switch languageID
      when 'python' then 'self.'
      when 'cofeescript' then '@'
      else 'this.'
    if context?.stringReferences? and missingReference[1] in context.stringReferences
      hint = "You may need quotes. Did you mean \"#{missingReference[1]}\"?"
    else if context?.thisMethods? and missingReference[1] in context.thisMethods
      hint = "Did you mean #{thisValueAccess}#{missingReference[1]}()?"
    else if context?.thisProperties? and missingReference[1] in context.thisProperties
      hint = "Did you mean #{thisValueAccess}#{missingReference[1]}?"

  [msg, hint]


# Esprima Harmony's error messages track V8's
# https://github.com/ariya/esprima/blob/harmony/esprima.js#L194

# JSHint's error and warning messages
# https://github.com/jshint/jshint/blob/master/src/messages.js
