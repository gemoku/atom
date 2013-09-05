fs = require 'fs'
path = require 'path'

AdmZip = require 'adm-zip'
request = require 'request'

module.exports = (grunt) ->
  {spawn, mkdir, rm, cp} = require('./task-helpers')(grunt)

  getAtomShellVersion = ->
    versionPath = path.join('atom-shell', 'version')
    if grunt.file.isFile(versionPath)
      grunt.file.read(versionPath).trim()
    else
      null

  getCachePath = (version) -> "/tmp/atom-cached-atom-shells/#{version}"

  isAtomShellVersionCached = (version) ->
    grunt.file.isDir(getCachePath(version))

  downloadAtomShell = (version, callback) ->
    downloadUrl = "https://gh-contractor-zcbenz.s3.amazonaws.com/atom-shell/#{version}/atom-shell-#{version}-darwin.zip"

    inputStream = request(downloadUrl)
    inputStream.on 'response', (response) ->
      if response.statusCode is 200
        grunt.log.writeln("Downloading atom-shell version #{version.cyan}")
        cachePath = "#{getCachePath(version)}/atom-shell.zip"
        mkdir(path.dirname(cachePath))
        outputStream = fs.createWriteStream(cachePath)
        outputStream.on 'close', -> callback(null, cachePath)
        inputStream.pipe(outputStream)
      else
        if response.statusCode is 404
          grunt.log.error("atom-shell #{version.cyan} not found")
        else
          grunt.log.error("atom-shell #{version.cyan} request failed")
        callback(false)

  unzipAtomShell = (zipPath, callback) ->
    grunt.log.writeln('Unzipping atom-shell')
    directoryPath = path.dirname(zipPath)
    inputStream = fs.createReadStream(zipPath)
    inputStream.on 'close', -> callback()
    inputStream.on 'error', -> callback(new Error("Unzipping #{zipPath} failed"))

    try
      zip = new AdmZip(zipPath);
      zip.extractAllTo(directoryPath, true)
      rm(zipPath, force: true)
    catch error
      callback(error)

  rebuildNativeModules = (previousVersion, callback) ->
    newVersion = getAtomShellVersion()
    if newVersion and newVersion isnt previousVersion
      grunt.log.writeln("Rebuilding native modules for new atom-shell version #{newVersion.cyan}.")
      cmd = path.join('node_modules', '.bin', 'apm')
      spawn {cmd, args: ['rebuild']}, (error) -> callback(error)
    else
      callback()

  installAtomShell = (version) ->
    rm('atom-shell')
    cp(getCachePath(version), 'atom-shell')

  grunt.registerTask 'update-atom-shell', 'Update atom-shell', ->
    done = @async()
    {atomShellVersion} = grunt.file.readJSON('package.json')
    currentAtomShellVersion = getAtomShellVersion()
    if atomShellVersion
      atomShellVersion = "v#{atomShellVersion}"
      if atomShellVersion isnt getAtomShellVersion()
        if isAtomShellVersionCached(atomShellVersion)
          grunt.log.writeln("Installing cached atom-shell #{atomShellVersion.cyan}")
          installAtomShell(atomShellVersion)
          rebuildNativeModules(currentAtomShellVersion, done)
        else
          downloadAtomShell atomShellVersion, (error, zipPath) ->
            if zipPath?
              unzipAtomShell zipPath, (error) ->
                if error?
                  done(false)
                else
                  grunt.log.writeln("Installing atom-shell #{atomShellVersion.cyan}")
                  installAtomShell(atomShellVersion)
                  rebuildNativeModules(currentAtomShellVersion, done)
            else
              done(false)
    else
      grunt.log.error("atom-shell version missing from package.json")
      done(false)
