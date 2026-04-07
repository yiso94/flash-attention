@echo off
setlocal enabledelayedexpansion

set MAX_JOBS=1

:parseArgs
rem Assigning a value to MAX_JOBS via a variable does not work in ninja, I don't know why
rem if [%1] == [WORKERS] set MAX_JOBS=%2 & shift & shift & goto :parseargs
if "%~1" == "FORCE_CXX11_ABI" (
    set "FLASH_ATTENTION_FORCE_CXX11_ABI=%~2"
    shift & shift
    goto :parseArgs
)
if "%~1" == "CUDA_ARCH" (
    set "FLASH_ATTN_CUDA_ARCHS=%~2"
    shift & shift
    goto :parseArgs
)
goto :buildContinue
:end

:buildFinalize
set MAX_JOBS=
set BUILD_TARGET=
set DISTUTILS_USE_SDK=
set FLASH_ATTENTION_FORCE_BUILD=
set FLASH_ATTENTION_FORCE_CXX11_ABI=
set dist_dir=
set FLASH_ATTN_CUDA_ARCHS=
set tmpname=
endlocal
goto :eof
:end

:buildContinue
echo MAX_JOBS: %MAX_JOBS%
echo FLASH_ATTENTION_FORCE_CXX11_ABI: %FLASH_ATTENTION_FORCE_CXX11_ABI%
echo FLASH_ATTN_CUDA_ARCHS: %FLASH_ATTN_CUDA_ARCHS%
rem # We want setuptools >= 49.6.0 otherwise we can't compile the extension if system CUDA version is 11.7 and pytorch cuda version is 11.6
rem # https://github.com/pytorch/pytorch/blob/664058fa83f1d8eede5d66418abff6e20bd76ca8/torch/utils/cpp_extension.py#L810
rem # However this still fails so I'm using a newer version of setuptools
rem pip install setuptools==68.0.0
pip install "setuptools>=49.6.0" packaging wheel psutil
rem # Limit MAX_JOBS otherwise the github runner goes OOM
rem # CUDA 11.8 can compile with 2 jobs, but CUDA 12.3 goes OOM
set FLASH_ATTENTION_FORCE_BUILD=TRUE
set BUILD_TARGET=cuda
set DISTUTILS_USE_SDK=1
set dist_dir=dist
rem set FLASH_ATTN_CUDA_ARCHS=80;120

python setup.py bdist_wheel --dist-dir=%dist_dir%
rem rename whl
rem just major version, such as cu12torch24cxx11abiFALSE
rem for /f "delims=" %%i in ('python -c "import sys; from packaging.version import parse; import torch; python_version = f'cp{sys.version_info.major}{sys.version_info.minor}'; cxx11_abi=str(torch._C._GLIBCXX_USE_CXX11_ABI).upper(); torch_cuda_version = parse(torch.version.cuda); torch_cuda_version = parse(\"11.8\") if torch_cuda_version.major == 11 else parse(\"12.4\"); cuda_version = f'{torch_cuda_version.major}'; torch_version_raw = parse(torch.__version__); torch_version = f'{torch_version_raw.major}.{torch_version_raw.minor}'; wheel_filename = f'cu{cuda_version}torch{torch_version}cxx11abi{cxx11_abi}'; print(wheel_filename);"') do set wheel_filename=%%i
rem such as cu124torch240cxx11abiFALSE
for /f "delims=" %%i in ('python -c "import sys; from packaging.version import parse; import torch; python_version = f'cp{sys.version_info.major}{sys.version_info.minor}'; cxx11_abi=str(torch._C._GLIBCXX_USE_CXX11_ABI).upper(); torch_cuda_version = parse(torch.version.cuda); cuda_version = \"\".join(map(str, torch_cuda_version.release)); torch_version_raw = parse(torch.__version__); torch_version = \".\".join(map(str, torch_version_raw.release)); wheel_filename = f'cu{cuda_version}torch{torch_version}cxx11abi{cxx11_abi}'; print(wheel_filename);"') do set wheel_filename=%%i

set tmpname=%wheel_filename%


for %%i in (%dist_dir%\*.whl) do (
    set "filename=%%~nxi"
    
    rem check if contains +
    echo !filename! | findstr /c:+ >nul
    if errorlevel 1 (
        rem replace second '-' to wheel_filename
        set "count=0"
        for /l %%j in (0, 1, 1000) do (
            if "!filename:~%%j,1!"=="-" set /a count+=1
            if "!filename:~%%j,1!"=="-" if "!count!"=="2" (
                set "new_filename=!filename:~0,%%j!+%tmpname%!filename:~%%j!"

                echo Renaming !filename! to !new_filename!
                move "%%i" "!dist_dir!/!new_filename!"
                goto :next
            )
        )
    )
    :next
    rem continue
)

goto :buildFinalize
:end