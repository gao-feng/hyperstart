#!/bin/bash

resultdir=`pwd`/result
mkdir result
cd ./build-kernel-image

kernelversion=`awk '{print $1}' ./kernel_version`
kerneldir="linux-$kernelversion"
kerneltar="$kerneldir.tar.gz"
echo $kernelversion, $kerneldir, $kerneltar

cat > Dockerfile << EOF
FROM ubuntu:14.04
MAINTAINER Gao feng <feng@hyper.sh>

RUN apt-get update
RUN apt-get -y upgrade
RUN apt-get -y install libncurses-dev make gcc wget bc autoconf 

RUN mkdir /root/build/
ADD https://cdn.kernel.org/pub/linux/kernel/v4.x/$kerneltar /root/
#COPY ./$kerneltar /root/
RUN tar -zxvf /root/$kerneltar -C /root/build
RUN rm /root/$kerneltar
COPY ./kernel_config /root/build/$kerneldir/.config
ADD https://github.com/hyperhq/hyperstart/archive/master.tar.gz /root/
#COPY ./master.tar.gz /root/
RUN tar -zxvf /root/master.tar.gz -C /root/build
RUN rm /root/master.tar.gz
COPY ./builder.sh /root/build/
WORKDIR /root/build
ENTRYPOINT ["/root/build/builder.sh", "$kernelversion"]
EOF

cat Dockerfile

cat > builder.sh <<'EOF'
#!/bin/bash

workdir="/root/build/"
kernelversion="$1"

kerneldir="$workdir/linux-$kernelversion"
bzImage="$kerneldir/arch/x86_64/boot/bzImage"
moduledir="$workdir/modules"
hyperstartdir="$workdir/hyperstart-master/"

cd $kerneldir
make menuconfig
localversion=`awk -F'"' '/CONFIG_LOCALVERSION/ {print $2}' .config`
make modules
make
rm -rf $moduledir
mkdir -p $moduledir
make modules_install INSTALL_MOD_PATH="$moduledir"

cd $workdir

tar -zxvf master.tar.gz
cd "$hyperstartdir"

cp -f "$bzImage" build/kernel
rm -rf build/modules/*
cp -r "$moduledir/lib/modules/$kernelversion$localversion" build/modules
rm -rf build/modules/$kernelversion$localversion/build
rm -rf build/modules/$kernelversion$localversion/source
./autogen.sh
./configure
make
cp build/kernel /tmp/result/
cp build/hyper-initrd.img /tmp/result/
EOF

cat builder.sh
chmod a+x builder.sh

imageid=`hyperctl build . 2>&1 |awk '{ if (/Successfully built/) print $3; else print $0 > "/dev/stderr";}'`
echo "image id is $imageid"

if [ x"$imageid" = x ]; then
	echo "null builder image id"
	exit
fi

cat > build.pod << EOF
{
	"containers": [{
		"image": "$imageid",
		"volumes":[{
			"volume": "result",
			"path": "/tmp/result/",
			"readOnly": false
		}]
	}],
	"resource":{
		"vcpu": "1",
		"memory": 2048
	},
	"volumes": [{
		"name": "result",
		"source": "$resultdir",
		"driver": "vfs"
	}],
	"tty": true
}
EOF

cat build.pod

hyperctl run --rm -a -p build.pod
ls $resultdir
hyperctl rmi "$imageid"
