set -e
set -x

ROOT_DIR="/home/tensorflow-2.13.0"

function print_output {
  if [ -z OMIT_PRINTING_OUTPUT_PATHS ]; then
    echo "Output can be found here:"
    for i in "$@"
    do
      # Check if the file exist.
      ls -1a ${ROOT_DIR}/$i
    done
  fi
}

function generate_tflite_so {
  pushd ${TMP_DIR} > /dev/null

  # Copy custom BUILD file
  cp ${ROOT_DIR}/custom_files/BUILD_tfliteops ${TMP_DIR}/BUILD
  
  # Build the so package.
  popd > /dev/null

  bazel ${CACHE_DIR_FLAG} build -c opt --cxxopt='--std=c++17' \
        --config=${TARGET_ARCHS} \
        //tmp:tensorflowlite \
        --verbose_failures

   OUT_FILES="${OUT_FILES} bazel-bin/tmp/tensorflowlite.so"
}

function generate_flex_so {
  pushd ${TMP_DIR}

  # Copy custom BUILD file
  cp ${ROOT_DIR}/custom_files/BUILD_tfops ${TMP_DIR}/BUILD

  popd

  # Build the so package.
  bazel ${CACHE_DIR_FLAG} build -c opt --cxxopt='--std=c++17' \
      --config=${TARGET_ARCHS} \
      --host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
      //tmp:tensorflowlite_flex \
      --verbose_failures

  OUT_FILES="${OUT_FILES} bazel-bin/tmp/tensorflowlite_flex.so"
}

# Check command line flags.
#TARGET_ARCHS=x86_64,arm64-v8a,armeabi-v7a
TARGET_ARCHS=android_arm64
# If the environmant variable BAZEL_CACHE_DIR is set, use it as the user root
# directory of bazel.
if [ ! -z ${BAZEL_CACHE_DIR} ]; then
  CACHE_DIR_FLAG="--output_user_root=${BAZEL_CACHE_DIR}/cache"
fi

if [ "$#" -gt 4 ]; then
  echo "ERROR: Too many arguments."
  print_usage
fi

for i in "$@"
do
case $i in
    --input_models=*)
      FLAG_MODELS="${i#*=}"
      shift;;
    --target_archs=*)
      TARGET_ARCHS="${i#*=}"
      shift;;
    --tflite_custom_ops_srcs=*)
      FLAG_TFLITE_OPS_SRCS="${i#*=}"
      shift;;
    --tflite_custom_ops_deps=*)
      FLAG_TFLITE_OPS_DEPS="${i#*=}"
      shift;;
    *)
      echo "ERROR: Unrecognized argument: ${i}"
      print_usage;;
esac
done

# Check if users already run configure
cd $ROOT_DIR
if [ ! -f "$ROOT_DIR/.tf_configure.bazelrc" ]; then
  echo "ERROR: Please run ./configure first."
  exit 1
else
  if ! grep -q ANDROID_SDK_HOME "$ROOT_DIR/.tf_configure.bazelrc"; then
    echo "ERROR: Please run ./configure with Android config."
    exit 1
  fi
fi

# Build the standard aar package of no models provided.
if [ -z ${FLAG_MODELS} ]; then
  bazel ${CACHE_DIR_FLAG} build -c opt --cxxopt='--std=c++17' \
    --config=${TARGET_ARCHS} \
    //tensorflow/lite:tensorflowlite \
    --verbose_failures

  print_output bazel-bin/tmp/tensorflowlite.so
  exit 0
fi

# Prepare the tmp directory.
mkdir -p tmp
TMP_DIR="${ROOT_DIR}/tmp/"

# Copy models to tmp directory.
MODEL_NAMES=""
for model in $(echo ${FLAG_MODELS} | sed "s/,/ /g")
do
  cp ${model} ${TMP_DIR}
  MODEL_NAMES="${MODEL_NAMES},$(basename ${model})"
done


# Copy srcs of additional tflite ops to tmp directory.
TFLITE_OPS_SRCS=""
for src_file in $(echo ${FLAG_TFLITE_OPS_SRCS} | sed "s/,/ /g")
do
  cp ${src_file} ${TMP_DIR}
  TFLITE_OPS_SRCS="${TFLITE_OPS_SRCS},$(basename ${src_file})"
done

# Build the custom so package.
generate_tflite_so

# Build flex so if one of the models contain flex ops.
bazel ${CACHE_DIR_FLAG} build -c opt \
  //tensorflow/lite/tools:list_flex_ops_no_kernel_main
bazel-bin/tensorflow/lite/tools/list_flex_ops_no_kernel_main \
  --graphs=${FLAG_MODELS} > ${TMP_DIR}/ops_list.txt
if [[ `cat ${TMP_DIR}/ops_list.txt` != "[]" ]]; then
  generate_flex_so
fi

# List the output files.
print_output ${OUT_FILES}
