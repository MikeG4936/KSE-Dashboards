@echo off
setlocal EnableExtensions DisableDelayedExpansion
pushd "%~dp0"
if errorlevel 1 (
  echo Could not open the folder containing this launcher.
  pause
  exit /b 1
)
if exist ".venv-windows\Scripts\python.exe" goto pillow
py -3 -c "import sys; sys.exit(sys.version_info < (3,9))" >nul 2>&1
if not errorlevel 1 goto create_py
python -c "import sys; sys.exit(sys.version_info < (3,9))" >nul 2>&1
if not errorlevel 1 goto create_python
echo Python 3.9 or newer is required.
echo Install Python from https://www.python.org/downloads/windows/ and try again.
goto failure

:create_py
echo Preparing the image resizer - first run only...
py -3 -m venv ".venv-windows"
if errorlevel 1 goto failure
goto pillow

:create_python
echo Preparing the image resizer - first run only...
python -m venv ".venv-windows"
if errorlevel 1 goto failure

:pillow
".venv-windows\Scripts\python.exe" -c "from PIL import Image; Image.Resampling.LANCZOS" >nul 2>&1
if not errorlevel 1 goto run
echo Installing Pillow - internet access is needed on the first run...
".venv-windows\Scripts\python.exe" -m pip install --disable-pip-version-check --upgrade Pillow
if errorlevel 1 goto failure

:run
".venv-windows\Scripts\python.exe" "resize_kse_images.py" --interactive %*
set "kse_exit=%errorlevel%"
echo.
pause
popd
exit /b %kse_exit%

:failure
echo Setup could not finish. Review the message above and try again.
echo.
pause
popd
exit /b 1
