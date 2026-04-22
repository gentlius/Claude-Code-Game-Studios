@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d d:\Github\ta\gdextension
set SCONS="C:\Users\joywo\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\Scripts\scons.exe"
%SCONS% platform=windows target=template_debug arch=x86_64
echo EXIT_CODE=%ERRORLEVEL%
