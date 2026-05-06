@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  Python 3.12 Embedded Environment Installer
::  Installs Python + all required packages into a "python"
::  folder in the same directory as this script.
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "PYTHON_DIR=%SCRIPT_DIR%python"
set "PYTHON_EXE=%PYTHON_DIR%\python.exe"
set "PIP_EXE=%PYTHON_DIR%\Scripts\pip.exe"
set "PYTHON_VERSION=3.12.10"
set "PYTHON_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-embed-amd64.zip"
set "GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py"
set "PYTHON_ZIP=%SCRIPT_DIR%python_embed.zip"
set "GET_PIP_SCRIPT=%SCRIPT_DIR%get-pip.py"

echo.
echo  =========================================================
echo   Python 3.12 Environment Installer
echo  =========================================================
echo.
echo  Install directory: %PYTHON_DIR%
echo.

:: Check if already installed
if exist "%PYTHON_EXE%" (
    echo  [INFO] Python already found at %PYTHON_EXE%
    echo  [INFO] Skipping download. Delete the "python" folder to reinstall.
    echo.
    goto :install_packages
)

:: Check for curl availability
where curl >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] curl is not available on this system.
    echo          Please install curl or use Windows 10 version 1803 or newer.
    pause
    exit /b 1
)

:: -----------------------------------------------------------
:: Step 1 - Download Python embeddable package
:: -----------------------------------------------------------
echo  [1/4] Downloading Python %PYTHON_VERSION% embeddable package...
curl -L --progress-bar -o "%PYTHON_ZIP%" "%PYTHON_URL%"
if errorlevel 1 (
    echo  [ERROR] Failed to download Python. Check your internet connection.
    pause
    exit /b 1
)
echo  [OK] Download complete.
echo.

:: -----------------------------------------------------------
:: Step 2 - Extract Python
:: -----------------------------------------------------------
echo  [2/4] Extracting Python to: %PYTHON_DIR%
if not exist "%PYTHON_DIR%" mkdir "%PYTHON_DIR%"
tar -xf "%PYTHON_ZIP%" -C "%PYTHON_DIR%"
if errorlevel 1 (
    echo  [ERROR] Extraction failed. Ensure you are on Windows 10 v1803+ or have tar installed.
    pause
    exit /b 1
)
del "%PYTHON_ZIP%"
echo  [OK] Extraction complete.
echo.

:: -----------------------------------------------------------
:: Step 3 - Enable site-packages (edit ._pth file)
:: -----------------------------------------------------------
echo  [3/4] Configuring Python environment...

:: Find and patch the ._pth file to enable site-packages and pip
for %%F in ("%PYTHON_DIR%\python3*._pth") do (
    set "PTH_FILE=%%F"
)
if not defined PTH_FILE (
    echo  [ERROR] Could not find the Python ._pth configuration file.
    pause
    exit /b 1
)

:: Uncomment import site line and add Scripts to path
powershell -NoProfile -Command ^
    "(Get-Content '!PTH_FILE!') -replace '#import site', 'import site' | Set-Content '!PTH_FILE!'"
if errorlevel 1 (
    echo  [ERROR] Failed to patch the ._pth file.
    pause
    exit /b 1
)
echo  [OK] site-packages enabled.
echo.

:: -----------------------------------------------------------
:: Step 4 - Install pip
:: -----------------------------------------------------------
echo  [4/4] Installing pip...
curl -L --progress-bar -o "%GET_PIP_SCRIPT%" "%GET_PIP_URL%"
if errorlevel 1 (
    echo  [ERROR] Failed to download get-pip.py.
    pause
    exit /b 1
)

"%PYTHON_EXE%" "%GET_PIP_SCRIPT%" --no-warn-script-location
if errorlevel 1 (
    echo  [ERROR] pip installation failed.
    pause
    exit /b 1
)
del "%GET_PIP_SCRIPT%"
echo  [OK] pip installed successfully.
echo.

:: -----------------------------------------------------------
:: Install packages
:: -----------------------------------------------------------
:install_packages

echo  =========================================================
echo   Installing required Python packages...
echo  =========================================================
echo.

if not exist "%PIP_EXE%" (
    echo  [ERROR] pip not found at: %PIP_EXE%
    echo          Something went wrong with the pip installation step.
    pause
    exit /b 1
)

:: Write the requirements to a temp file next to the script
set "REQ_FILE=%SCRIPT_DIR%_requirements_temp.txt"

(
echo absl-py==2.4.0
echo aiohappyeyeballs==2.6.1
echo aiohttp==3.13.5
echo aiosignal==1.4.0
echo attrs==26.1.0
echo backoff==2.2.1
echo boto3==1.42.44
echo botocore==1.42.44
echo certifi==2026.1.4
echo charset-normalizer==3.4.4
echo click==8.3.1
echo colorama==0.4.6
echo contourpy==1.3.3
echo cycler==0.12.1
echo dataclasses-json==0.6.7
echo defusedxml==0.7.1
echo filelock==3.25.2
echo filetype==1.2.0
echo fire==0.7.1
echo flatbuffers==25.12.19
echo fonttools==4.61.1
echo frozenlist==1.8.0
echo fsspec==2026.2.0
echo gitdb==4.0.12
echo GitPython==3.1.46
echo grpcio==1.78.0
echo huggingface-hub==0.24.7
echo idna==3.7
echo inference-sdk==1.2.1
echo Jinja2==3.1.6
echo jmespath==1.1.0
echo kiwisolver==1.4.9
echo Markdown==3.10.1
echo MarkupSafe==3.0.3
echo marshmallow==3.26.2
echo matplotlib==3.10.8
echo mpmath==1.3.0
echo multidict==6.7.1
echo mypy_extensions==1.1.0
echo networkx==3.6.1
echo numpy
echo onnxruntime==1.24.4
echo opencv-python==4.10.0.84
echo packaging==26.0
echo pandas==3.0.0
echo pi_heif==1.2.0
echo pillow
echo pillow-avif-plugin==1.5.5
echo polars==1.38.0
echo propcache==0.4.1
echo protobuf==6.33.5
echo psutil==7.2.2
echo py-cpuinfo==9.0.0
echo pybboxes==0.1.6
echo pyDeprecate==0.5.0
echo pyparsing==3.3.2
echo python-dateutil==2.9.0.post0
echo python-dotenv==1.2.1
echo PyYAML==6.0.3
echo requests==2.32.5
echo requests-toolbelt==1.0.0
echo roboflow==1.2.13
echo s3transfer==0.16.0
echo sahi==0.11.36
echo scipy==1.17.0
echo seaborn==0.13.2
echo setuptools==70.2.0
echo shapely==2.1.2
echo six==1.17.0
echo smmap==5.0.2
echo supervision==0.27.0.post2
echo sympy==1.13.1
echo tensorboard==2.20.0
echo tensorboard-data-server==0.7.2
echo termcolor==3.3.0
echo terminaltables==3.1.10
echo thop==0.1.1.post2209072238
echo tqdm==4.67.3
echo typing-inspect==0.9.0
echo typing_extensions==4.15.0
echo tzdata==2025.3
echo ultralytics==8.4.12
echo ultralytics-thop==2.0.18
echo urllib3==2.6.3
echo Werkzeug==3.1.5
echo yarl==1.23.0
echo yolov5==7.0.14
) > "%REQ_FILE%"

echo  Installing packages (this may take several minutes)...
echo.

"%PIP_EXE%" install --no-warn-script-location -r "%REQ_FILE%"
if errorlevel 1 (
    echo.
    echo  [WARNING] One or more packages may have failed to install.
    echo            Review the output above for details.
    echo            Some packages like onnxruntime-directml and onnxruntime-gpu
    echo            may conflict - this is normal. onnxruntime was installed instead.
) else (
    echo.
    echo  [OK] All packages installed successfully.
)

del "%REQ_FILE%"

:: -----------------------------------------------------------
:: Done
:: -----------------------------------------------------------
echo.
echo  =========================================================
echo   Installation Complete!
echo  =========================================================
echo.
echo  Python executable location:
echo    %PYTHON_EXE%
echo.
echo  You can reference this path in your application.
echo.
pause
exit /b 0
