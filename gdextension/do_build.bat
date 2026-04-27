@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d d:\Github\ta\gdextension
"C:\Users\joywo\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\Scripts\scons.exe" platform=windows target=template_debug arch=x86_64
echo BUILD_EXIT=%ERRORLEVEL%
