# Fictional fixture build script. Exists so the .vscode/tasks.json build task points at a real
# file; /alrig:scan reads the task, it never runs this.
param([string]$Project = 'app')
Write-Host "would compile $Project"
