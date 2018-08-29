FROM centos:7

EXPOSE 9000-9001

RUN yum install -y epel-release # needed for the 'jq' package
RUN yum install -y socat jq file java net-tools # 'file' required by lgto but not listed as dep

COPY lgtoclnt-9.2.1.4-1.x86_64.rpm \
     lgtoserv-9.2.1.4-1.x86_64.rpm \
     lgtonode-9.2.1.4-1.x86_64.rpm \
     lgtoxtdclnt-9.2.1.4-1.x86_64.rpm \
     lgtoman-9.2.1.4-1.x86_64.rpm \
     lgtoauthc-9.2.1.4-1.x86_64.rpm \
     lgtonmc-9.2.1.4-1.x86_64.rpm /

RUN yum localinstall --nogpgcheck -y /lgtoclnt-9.2.1.4-1.x86_64.rpm \
                                     /lgtoserv-9.2.1.4-1.x86_64.rpm \
                                     /lgtonode-9.2.1.4-1.x86_64.rpm \
                                     /lgtoxtdclnt-9.2.1.4-1.x86_64.rpm \
                                     /lgtoman-9.2.1.4-1.x86_64.rpm \
                                     /lgtoauthc-9.2.1.4-1.x86_64.rpm \
                                     /lgtonmc-9.2.1.4-1.x86_64.rpm

RUN yum clean all && rm -f /lgto*.rpm

COPY authc_configure.resp /

COPY recover.sh /
COPY bootstrap.sh /
COPY mask_devices.nsradmin /

ENV RecoveryAreaGid 4
ENV RecoveryArea /recovery_area
ENV RecoverySocket "unix-listen:$RecoveryArea/networker.socket,reuseaddr,fork,mode=0600,unlink-early=1"

ENTRYPOINT [ "/bootstrap.sh" ]
