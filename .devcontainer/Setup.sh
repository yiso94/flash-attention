#!/usr/bin/env bash
set -e

export MAX_JOBS=4
export FLASH_ATTENTION_FORCE_CXX11_ABI=true
export FLASH_ATTN_CUDA_ARCHS="89"

echo "MAX_JOBS: $MAX_JOBS"
echo "FLASH_ATTENTION_FORCE_CXX11_ABI: $FLASH_ATTENTION_FORCE_CXX11_ABI"
echo "FLASH_ATTN_CUDA_ARCHS: $FLASH_ATTN_CUDA_ARCHS"

pip install "setuptools>=49.6.0" packaging wheel psutil
pip install numpy==1.26.4
pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/cu130

# build設定
export FLASH_ATTENTION_FORCE_BUILD=TRUE
export BUILD_TARGET=cuda
export DISTUTILS_USE_SDK=1

dist_dir=dist
mkdir -p $dist_dir

# build
rm -rf build
rm -rf $dist_dir
python3 setup.py bdist_wheel --dist-dir=$dist_dir

# -----------------------------
# wheel名生成（batと完全一致）
# -----------------------------
wheel_filename=$(python3 - <<'EOF'
import sys
from packaging.version import parse
import torch

python_version = f'cp{sys.version_info.major}{sys.version_info.minor}'
cxx11_abi = str(torch._C._GLIBCXX_USE_CXX11_ABI).upper()

torch_cuda_version = parse(torch.version.cuda)
cuda_version = "".join(map(str, torch_cuda_version.release))

torch_version_raw = parse(torch.__version__)
torch_version = ".".join(map(str, torch_version_raw.release))

wheel_filename = f'cu{cuda_version}torch{torch_version}cxx11abi{cxx11_abi}'
print(wheel_filename)
EOF
)

# batと同じ変数名
tmpname="$wheel_filename"

# -----------------------------
# rename処理（完全再現）
# -----------------------------
shopt -s nullglob

for file in "$dist_dir"/*.whl; do
    filename=$(basename "$file")

    # '+' を含むかチェック（batの findstr 相当）
    if [[ "$filename" != *"+"* ]]; then
        count=0

        # batの for /l %%j を再現
        for ((j=0; j<1000; j++)); do
            char="${filename:$j:1}"

            if [[ "$char" == "-" ]]; then
                ((count++))
            fi

            if [[ "$char" == "-" && $count -eq 2 ]]; then
                prefix="${filename:0:$j}"
                suffix="${filename:$j}"
                new_filename="${prefix}+${tmpname}${suffix}"

                echo "Renaming $filename to $new_filename"
                mv "$file" "$dist_dir/$new_filename"
                break
            fi
        done
    fi
done

# -----------------------------
# buildFinalize
# -----------------------------
unset MAX_JOBS
unset BUILD_TARGET
unset DISTUTILS_USE_SDK
unset FLASH_ATTENTION_FORCE_BUILD
unset FLASH_ATTENTION_FORCE_CXX11_ABI
unset dist_dir
unset FLASH_ATTN_CUDA_ARCHS
unset tmpname