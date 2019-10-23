ARG WINE_VER
FROM wine:$WINE_VER

# clang-cl shims
RUN mkdir /etc/vcclang && \
    touch /etc/vcclang/vcvars32 && \
    touch /etc/vcclang/vcvars64
ADD dockertools/clang-cl /usr/local/bin/clang-cl
ADD dockertools/lld-link /usr/local/bin/lld-link    
RUN clang-cl --version
RUN lld-link --version

# vcwine
RUN mkdir /etc/vcwine && \
    touch /etc/vcwine/vcvars32 && \
    touch /etc/vcwine/vcvars64
ADD dockertools/vcwine /usr/local/bin/vcwine

# bring over the msvc snapshots
ARG MSVC
ENV MSVC=$MSVC
ADD build/msvc$MSVC/snapshots snapshots

RUN ls -la $HOME
RUN ls -la $HOME/snapshots/*

# import the msvc snapshot files
RUN cd $WINEPREFIX/drive_c && \
    unzip -n $HOME/snapshots/CMP/files.zip
RUN cd $WINEPREFIX/drive_c && mkdir -p Windows && \
    cd $WINEPREFIX/drive_c/Windows && mkdir -p INF System32 SysWOW64 WinSxS && \
    mv INF      inf && \
    mv System32 system32 && \
    mv SysWOW64 syswow64 && \
    mv WinSxS   winsxs && \
    cd $WINEPREFIX/drive_c && \
    cp -R $WINEPREFIX/drive_c/Windows/* $WINEPREFIX/drive_c/windows && \
    rm -rf $WINEPREFIX/drive_c/Windows

# import msvc environment snapshot
ADD dockertools/diffenv diffenv
ADD dockertools/make-vcclang-vars make-vcclang-vars
RUN ./diffenv $HOME/snapshots/SNAPSHOT-01/env.txt $HOME/snapshots/SNAPSHOT-02/vcvars32.txt /etc/vcwine/vcvars32 && \
    ./make-vcclang-vars /etc/vcwine/vcvars32 /etc/vcclang/vcvars32
RUN ./diffenv $HOME/snapshots/SNAPSHOT-01/env.txt $HOME/snapshots/SNAPSHOT-02/vcvars64.txt /etc/vcwine/vcvars64 && \
    ./make-vcclang-vars /etc/vcwine/vcvars64 /etc/vcclang/vcvars64
RUN rm diffenv make-vcclang-vars

# clean up
RUN rm -rf $HOME/snapshots

# 64-bit linking has trouble finding cvtres, so help it out
RUN find $WINEPREFIX -iname x86_amd64 | xargs -Ifile cp "file/../cvtres.exe" "file"

# workaround bugs in wine's cmd that prevents msvc setup bat files from working
ADD dockertools/hackvcvars hackvcvars
RUN find $WINEPREFIX/drive_c -iname v[cs]\*.bat | xargs -Ifile $HOME/hackvcvars "file" && \
    find $WINEPREFIX/drive_c -iname win\*.bat | xargs -Ifile $HOME/hackvcvars "file" && \
    rm hackvcvars

# fix inconsistent casing in msvc filenames
RUN find $WINEPREFIX -name Include -execdir mv Include include \; || \
    find $WINEPREFIX -name Lib -execdir mv Lib lib \; || \
    find $WINEPREFIX -name \*.Lib -execdir rename 'y/A-Z/a-z/' {} \;

# make sure we can compile with MSVC
ADD test test
RUN cd test && \
    MSVCARCH=32 vcwine cl helloworld.cpp && vcwine helloworld.exe && \
    MSVCARCH=64 vcwine cl helloworld.cpp && vcwine helloworld.exe && \
    vcwine cl helloworld.cpp && vcwine helloworld.exe && \
    cd .. && rm -rf test

# get _MSC_VER for use with clang-cl
ADD dockertools/msc_ver.cpp msc_ver.cpp
RUN vcwine cl msc_ver.cpp && \
    echo -n "MSC_VER=`vcwine msc_ver.exe`" >> /etc/vcclang/vcvars32  && \
    echo -n "MSC_VER=`vcwine msc_ver.exe`" >> /etc/vcclang/vcvars64  && \
    rm *.cpp

# make sure we can compile with clang-cl
ADD test test
RUN cd test && \
    if [ "$MSVC" -gt "10" ] ; then clang-cl helloworld.cpp && vcwine helloworld.exe ; fi && \
    cd .. && rm -rf test

# reboot for luck
RUN winetricks win10
RUN wineboot -r

# entrypoint
ENV MSVCARCH=64
ADD dockertools/vcentrypoint /usr/local/bin/vcentrypoint
ENTRYPOINT [ "/usr/local/bin/vcentrypoint" ]
