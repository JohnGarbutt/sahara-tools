#!/bin/bash -e

set -o pipefail

# Build and/or register an image for use with OpenStack sahara using Apache
# Spark on Ubuntu on baremetal.

BUILD=0
REGISTER=0
if [[ $# -gt 0 ]]; then
    if [[ $1 = build ]]; then
        BUILD=1
    elif [[ $1 = register ]]; then
        REGISTER=1
    else
        echo "???"
        exit 1
    fi
else
    BUILD=1
    REGISTER=1
fi

OS_DISTRO=${OS_DISTRO:-ubuntu}
case $OS_DISTRO in
    ubuntu)
        export DIB_RELEASE=${DIB_RELEASE:-trusty}
        ;;
    centos | centos7)
        ;;
    *)
        echo "Unexpected OS_DISTRO $OS_DISTRO"
        exit 1
        ;;
esac
PLUGIN=${PLUGIN:-spark}
SPARK_VERSION=${SPARK_VERSION:-1.6.0}
HADOOP_VERSION=${HADOOP_VERSION:-5.5}
case $PLUGIN in
    spark)
        PLUGIN_VERSION=${SPARK_VERSION}
        ;;
    vanilla)
        PLUGIN_VERSION=${HADOOP_VERSION}
        ;;
esac
EXTRA_ELEMENTS=${EXTRA_ELEMENTS:-}

IMAGE_NAME=${IMAGE_NAME:-sahara-${PLUGIN}-${PLUGIN_VERSION}-${OS_DISTRO}${DIB_RELEASE:+-${DIB_RELEASE}}}
FILENAME=${FILENAME:-$IMAGE_NAME}

# Support use of DIB elements from our repository.
export ELEMENTS_PATH=$(pwd)/stackhpc-image-elements/elements

# The following is required for --visibility and --os-distro arguments.
export OS_IMAGE_API_VERSION=2

if [[ ! -d stackhpc-image-elements ]]; then
    git clone https://github.com/stackhpc/stackhpc-image-elements
fi
if [[ ! -d sahara-image-elements ]]; then
    git clone https://github.com/stackhpc/sahara-image-elements \
        -b stackhpc-6.0.0.1
fi

virtualenv dib-venv
source dib-venv/bin/activate
pip install -U pip
pip install tox

cd sahara-image-elements

if [[ $BUILD -eq 1 ]]; then
    echo "Building image"
    case $PLUGIN in
      vanilla)
        case $OS_DISTRO in
          ubuntu)
            case $HADOOP_VERSION in
              2.7.1)
                export ubuntu_vanilla_hadoop_2_7_1_image_name=${FILENAME}
                ;;
              2.7.3)
                export ubuntu_vanilla_hadoop_2_7_3_image_name=${FILENAME}
                ;;
              2.8.0)
                export ubuntu_vanilla_hadoop_2_8_0_image_name=${FILENAME}
                ;;
            esac
            ;;
          centos)
            case $HADOOP_VERSION in
              2.7.1)
                export centos_vanilla_hadoop_2_7_1_image_name=${FILENAME}
                ;;
              2.7.3)
                export centos_vanilla_hadoop_2_7_3_image_name=${FILENAME}
                ;;
              2.8.0)
                export centos_vanilla_hadoop_2_8_0_image_name=${FILENAME}
                ;;
            esac
            ;;
          centos7)
            case $HADOOP_VERSION in
              2.7.1)
                export centos7_vanilla_hadoop_2_7_1_image_name=${FILENAME}
                ;;
              2.7.3)
                export centos7_vanilla_hadoop_2_7_3_image_name=${FILENAME}
                ;;
              2.8.0)
                export centos7_vanilla_hadoop_2_8_0_image_name=${FILENAME}
                ;;
            esac
            ;;
        esac
        ;;
      spark)
        case $OS_DISTRO in
          ubuntu)
            export ubuntu_spark_image_name=${FILENAME}
            ;;
          centos)
            export centos_spark_image_name=${FILENAME}
            ;;
          centos7)
            export centos7_spark_image_name=${FILENAME}
            ;;
        esac
        ;;
    esac
    tox -e venv -- \
      sahara-image-create \
      -p ${PLUGIN} \
      -i ${OS_DISTRO} \
      -s ${SPARK_VERSION} \
      -v ${HADOOP_VERSION} \
      -e ${EXTRA_ELEMENTS} \
      -x \
      -b
    echo "Built image"
fi

if [[ $REGISTER -eq 1 ]]; then
    echo "Registering images"
    FILENAME=centos7_sahara_vanilla_hadoop_2_8_2_latest
    KERNEL_ID=`glance image-create --name ${IMAGE_NAME}-kernel \
                                   --visibility public \
                                   --disk-format=aki \
                                   --container-format=aki \
                                   --file=${FILENAME}.vmlinuz \
                                   | grep id | tr -d '| ' | cut --bytes=3-57`
    RAMDISK_ID=`glance image-create --name ${IMAGE_NAME}-ramdisk \
                                    --visibility public \
                                    --disk-format=ari \
                                    --container-format=ari \
                                    --file=${FILENAME}.initrd \
                                    | grep id |  tr -d '| ' | cut --bytes=3-57`
    BASE_ID=`glance image-create --name ${IMAGE_NAME} \
                                    --os-distro ${OS_DISTRO} \
                                    --visibility public \
                                    --disk-format=qcow2 \
                                    --container-format=bare \
                                    --property kernel_id=$KERNEL_ID \
                                    --property ramdisk_id=$RAMDISK_ID \
                                    --file=${FILENAME}.qcow2 \
                                    | grep -v kernel | grep -v ramdisk \
                                    | grep id | tr -d '| ' | cut --bytes=3-57`
    echo "Registered images"
    echo "Kernel: $KERNEL_ID"
    echo "Ramdisk: $RAMDISK_ID"
    echo "Image: $BASE_ID"
fi
