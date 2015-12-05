version="$(wget -q -O - http://sourceforge.net/projects/opencvlibrary/files/opencv-unix | egrep -m1 -o '\"[0-9](\.[0-9]+)+(-[-a-zA-Z0-9]+)?' | cut -c2-)"
downloadfilelist="opencv-$version.tar.gz opencv-$version.zip"
downloadfile=
for file in $downloadfilelist;
do
        wget --spider http://sourceforge.net/projects/opencvlibrary/files/opencv-unix/$version/$file/download
        if [ $? -eq 0 ]; then
                downloadfile=$file
        fi
done
if [ -z "$downloadfile" ]; then
        echo "Could not find download file on sourceforge page.  Please find the download file for version $version at"
        echo "http://sourceforge.net/projects/opencvlibrary/files/opencv-unix/$version/ and update this script"
        exit  1
fi


arch=$(uname -m)
if [ "$arch" == "i686" -o "$arch" == "i386" -o "$arch" == "i486" -o "$arch" == "i586" ]; then
flag=1
else
flag=0
fi
echo "Installing OpenCV 2.4.9"
mkdir OpenCV
cd OpenCV
echo "Removing any pre-installed ffmpeg and x264"
sudo apt-get -y remove ffmpeg x264 libx264-dev
echo "Installing Dependenices"
sudo apt-get -y install libopencv-dev
sudo apt-get -y install build-essential checkinstall cmake pkg-config yasm
sudo apt-get -y install libtiff4-dev libjpeg-dev libjasper-dev
sudo apt-get -y install libavcodec-dev libavformat-dev libswscale-dev libdc1394-22-dev libxine-dev libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev libv4l-dev
sudo apt-get -y install python-dev python-numpy
sudo apt-get -y install libtbb-dev
sudo apt-get -y install libqt4-dev libgtk2.0-dev
sudo apt-get -y install libfaac-dev libmp3lame-dev libopencore-amrnb-dev libopencore-amrwb-dev libtheora-dev libvorbis-dev libxvidcore-dev
sudo apt-get -y install x264 v4l-utils ffmpeg
# sudo apt-get -y install libgtk2.0-dev # duplicate
echo "Downloading OpenCV 2.4.9"
wget -O OpenCV-2.4.9.zip http://sourceforge.net/projects/opencvlibrary/files/opencv-unix/2.4.9/opencv-2.4.9.zip/download
echo "Installing OpenCV 2.4.9"
unzip OpenCV-2.4.9.zip
cd opencv-2.4.9
mkdir build
cd build
cmake -D CMAKE_BUILD_TYPE=RELEASE -D CMAKE_INSTALL_PREFIX=/usr/local -D WITH_TBB=ON -D BUILD_NEW_PYTHON_SUPPORT=ON -D WITH_V4L=ON -D INSTALL_C_EXAMPLES=ON -D INSTALL_PYTHON_EXAMPLES=ON -D BUILD_EXAMPLES=ON -D WITH_QT=ON -D WITH_OPENGL=ON ..
make -j4
sudo make install
sudo sh -c 'echo "/usr/local/lib" > /etc/ld.so.conf.d/opencv.conf'
sudo ldconfig
cd ../../..
rm -rf OpenCV
echo "OpenCV 2.4.9 ready to be used"


if [[ -z "$version" ]]; then
	echo "Please define version before calling `basename $0` or use a wrapper like opencv_latest.sh"
	exit 1
fi
if [[ -z "$downloadfile" ]]; then
	echo "Please define downloadfile before calling `basename $0` or use a wrapper like opencv_latest.sh"
	exit 1
fi
if [[ -z "$dldir" ]]; then
	dldir=OpenCV
fi
echo "Installing OpenCV" $version
mkdir -p $dldir
cd $dldir
echo "Installing Dependencies"
sudo yum -y install http://dl.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
sudo yum -y groupinstall "Development Tools"
sudo yum -y install wget unzip opencv opencv-devel gtk2-devel cmake
if [ ! -f $downloadfile ]; then
	echo "Downloading OpenCV" $version
	wget -O $downloadfile http://sourceforge.net/projects/opencvlibrary/files/opencv-unix/$version/$downloadfile/download
fi
if [ ! -d opencv-$version ]; then
	echo "Installing OpenCV" $version
	echo $downloadfile | grep ".zip"
	if [ $? -eq 0 ]; then
		unzip $downloadfile
	else
		tar -xvf $downloadfile
	fi
fi
cd opencv-$version
cmake --version | grep " 2.6"
if [ $? -eq 0 ]; then
	# Delete lines beginning with string(MD5 based on incompatibility with cmake 2.6.  See 
	# http://answers.opencv.org/question/24095/building-opencv-247-on-centos-6/
	sed  -i '/string(MD5/d' cmake/cl2cpp.cmake
fi
mkdir -p build
cd build
cmake -D CMAKE_BUILD_TYPE=RELEASE -D CMAKE_INSTALL_PREFIX=/usr/local ..
make -j 4
sudo make install
sudo sh -c 'echo "/usr/local/lib" > /etc/ld.so.conf.d/opencv.conf'
sudo ldconfig