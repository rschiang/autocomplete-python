module.exports =
  selector: '.source.python'
  disableForSelector: '.source.python .comment, .source.python .string'
  inclusionPriority: 1
  suggestionPriority: 2
  excludeLowerPriority: true

  constructor: ->
    console.debug 'Preparing python completions...'
    @requests = {}

    env = process.env
    pythonPath = atom.config.get('autocomplete-python.pythonPath')

    windowsPaths = ['C:\\Python2.7',
                    'C:\\Python3.4',
                    'C:\\Python3.5',
                    'C:\\Program Files (x86)\\Python 2.7',
                    'C:\\Program Files (x86)\\Python 3.4',
                    'C:\\Program Files (x86)\\Python 3.5',
                    'C:\\Program Files (x64)\\Python 2.7',
                    'C:\\Program Files (x64)\\Python 3.4',
                    'C:\\Program Files (x64)\\Python 3.5',
                    'C:\\Program Files\\Python 2.7',
                    'C:\\Program Files\\Python 3.4',
                    'C:\\Program Files\\Python 3.5']
    unixPaths = ['/usr/local/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin']

    if /^win/.test(process.platform)
      path = env.PATH.split(';')
      if pythonPath and pythonPath not in path
        path.unshift(pythonPath)
      for p in windowsPaths
        if p not in path
          path.push(p)
      env.PATH = path.join(';')
    else
      path = env.PATH.split(':')
      if pythonPath and pythonPath not in path
        path.unshift(pythonPath)
      for p in unixPaths
        if p not in path
          path.push(p)
      env.PATH = path.join(':')

    @provider = require('child_process').spawn(
      'python', [__dirname + '/completion.py'], env: env)

    @provider.on 'error', (err) =>
      console.error "Python Provider error: #{err}"
      if err.code == 'ENOENT'
        atom.notifications.addError(
          'autocomplete-python unable to find python executable: please set ' +
          'the path to python directory manually in package settings and ' +
          'restart your editor. If issue persists please report it at: ' +
          'https://github.com/sadovnychyi/autocomplete-python/issues/new', {
            detail: err,
            dismissable: true})
      else
        throw "Python Provider error: #{err}"
    @provider.on 'exit', (code, signal) =>
      console.error "Python Provider exit with code #{code}, signal #{signal}"
      throw "Python Provider exit with code #{code}, signal #{signal}"
    @provider.stderr.on 'data', (err) ->
      console.error "Python Provider error: #{err}"

    @readline = require('readline').createInterface(input: @provider.stdout)
    @readline.on 'line', (response) => @_deserialize(response)

  _serialize: (request) ->
    return JSON.stringify(request)

  _deserialize: (response) ->
    response = JSON.parse(response)
    [resolve, reject] = @requests[response['id']]
    resolve(response['completions'])

  _generateRequestId: (editor, bufferPosition) ->
    return require('crypto').createHash('md5').update([
      editor.getPath(), editor.getText(), bufferPosition.row,
      bufferPosition.column].join()).digest('hex')

  _generateRequestConfig: () ->
    extraPaths = []

    for path in atom.config.get('autocomplete-python.extraPaths').split(';')
      for project in atom.project.getPaths()
        modified = path.replace('$PROJECT', project)
        if modified not in extraPaths
          extraPaths.push(modified)
    args =
      'extraPaths': extraPaths
      'useSnippets': atom.config.get(
        'autocomplete-python.useSnippets')
      'caseInsensitiveCompletion': atom.config.get(
        'autocomplete-python.caseInsensitiveCompletion')
      'addDotAfterModule': atom.config.get(
        'autocomplete-python.addDotAfterModule')
      'addBracketAfterFunction': atom.config.get(
        'autocomplete-python.addBracketAfterFunction')
    return args

  getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
    payload =
      id: @_generateRequestId(editor, bufferPosition)
      path: editor.getPath()
      source: editor.getText()
      line: bufferPosition.row
      column: bufferPosition.column
      config: @_generateRequestConfig()

    @provider.stdin.write(@_serialize(payload) + '\n')

    return new Promise (resolve, reject) =>
      @requests[payload.id] = [resolve, reject]

  dispose: ->
    @readline.close()
    @provider.kill()
