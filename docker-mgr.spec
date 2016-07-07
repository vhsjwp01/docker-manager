%define __os_install_post %{nil}
%define uek %( uname -r | egrep -i uek | wc -l | awk '{print $1}' )
%define rpm_arch %( uname -p )
%define rpm_author Jason W. Plummer
%define rpm_author_email jason.plummer@ingramcontent.com
%define distro_id %( lsb_release -is )
%define distro_ver %( lsb_release -rs )
%define distro_major_ver %( echo "%{distro_ver}" | awk -F'.' '{print $1}' )

Summary: A simple client-server method to invoke docker commands
Name: docker-manager
Release: 1.26.EL%{distro_major_ver}
License: GNU
Group: Docker/Management
BuildRoot: %{_tmppath}/%{name}-root
URL: https://stash.ingramcontent.com/projects/RPM/repos/docker-manager/browse
Version: 1.0
BuildArch: noarch

## These BuildRequires can be found in Base
##BuildRequires: zlib, zlib-devel 
#
## This block handles Oracle Linux UEK .vs. EL BuildRequires
#%if %{uek}
#BuildRequires: kernel-uek-devel, kernel-uek-headers
#%else
#BuildRequires: kernel-devel, kernel-headers
#%endif

# These Requires can be found in Base
Requires: bind-utils
Requires: gawk
Requires: nc
Requires: sed
Requires: xinetd

# These Requires can be found in EPEL
Requires: /usr/bin/docker

%define install_base /usr/local
%define install_bin_dir %{install_base}/bin
%define install_sbin_dir %{install_base}/sbin
%define install_xinetd_dir /etc/xinetd.d
%define install_initd_dir /etc/rc.d/init.d
%define docker_mgr_port 42000
%define remote_real_name docker-remote
%define mgr_real_name docker_mgr
%define xinetd_real_name docker-mgr
%define docker_constart_real_name docker-constart

Source0: ~/rpmbuild/SOURCES/docker-remote.sh
Source1: ~/rpmbuild/SOURCES/docker_mgr.sh
Source2: ~/rpmbuild/SOURCES/docker-mgr.xinetd
Source3: ~/rpmbuild/SOURCES/docker-constart.sh

%description
Docker-manager is a server side daemon called docker_mgr launched via
xinetd that responds to queries passed by a client side tool called
docker-remote.  It also includes an init script and command file that
can restart currently running docker containers following a reboot

%install
rm -rf %{buildroot}
# Populate %{buildroot}
mkdir -p %{buildroot}%{install_bin_dir}
cp %{SOURCE0} %{buildroot}%{install_bin_dir}/%{remote_real_name}
mkdir -p %{buildroot}%{install_sbin_dir}
cp %{SOURCE1} %{buildroot}%{install_sbin_dir}/%{mgr_real_name}
mkdir -p %{buildroot}%{install_xinetd_dir}
cp %{SOURCE2} %{buildroot}%{install_xinetd_dir}/%{xinetd_real_name}
mkdir -p %{buildroot}%{install_initd_dir}/
cp %{SOURCE3} %{buildroot}%{install_initd_dir}/%{docker_constart_real_name}

# Build packaging manifest
rm -rf /tmp/MANIFEST.%{name}* > /dev/null 2>&1
echo '%defattr(-,root,root)' > /tmp/MANIFEST.%{name}
chown -R root:root %{buildroot} > /dev/null 2>&1
cd %{buildroot}
find . -depth -type d -exec chmod 755 {} \;
find . -depth -type f -exec chmod 644 {} \;
for i in `find . -depth -type f | sed -e 's/\ /zzqc/g'` ; do
    filename=`echo "${i}" | sed -e 's/zzqc/\ /g'`
    eval is_exe=`file "${filename}" | egrep -i "executable" | wc -l | awk '{print $1}'`
    if [ "${is_exe}" -gt 0 ]; then
        chmod 555 "${filename}"
    fi
done
find . -type f -or -type l | sed -e 's/\ /zzqc/' -e 's/^.//' -e '/^$/d' > /tmp/MANIFEST.%{name}.tmp
for i in `awk '{print $0}' /tmp/MANIFEST.%{name}.tmp` ; do
    filename=`echo "${i}" | sed -e 's/zzqc/\ /g'`
    dir=`dirname "${filename}"`
    echo "${dir}/*"
done | sort -u >> /tmp/MANIFEST.%{name}
# Clean up what we can now and allow overwrite later
rm -f /tmp/MANIFEST.%{name}.tmp
chmod 666 /tmp/MANIFEST.%{name}

# RPM provides four hooks for injecting commands into the installation and uninstallation sequences: 
# two for installation and two for uninstallation. All hooks run on the target system and are generally 
# sufficient for most housekeeping chores. These four hooks are:
#
# - All commands listed in the %pre hook run before your package is installed.
# - Commands in the %post hook run after your package has been installed.
# - The %preun hook runs before your package is removed from the system.
# - Commands in the %postun hook run after your package is removed from the system.
#
# Hence, the order of operations during an upgrade is:
# 1 - Run the %pre section of the RPM being installed.
# 2 - Install the files that the RPM provides.
# 3 - Run the %post section of the RPM.
# 4 - Run the %preun of the old package.
# 5 - Delete any old files not overwritten by the newer version. (This step deletes files that the new package does not require.)
# 6 - Run the %postun hook of the old package.
#
# Steps 4 and 6 may seem a bit suspect, and for good reason: If you are upgrading a package, running 
# the older version's uninstallation hooks could undo portions or all of steps 1 through 3. In fact, 
# without conditions, the uninstallation hooks of the older version could destroy the newer version. 
# To prevent unintentional clobbering, RPM passes each hook one argument, a flag. The value of the flag 
# indicates which operation is being performed:
#
# - If the first argument to %pre is 1, the RPM operation is an initial installation. If the argument 
#   to %pre is 2, the operation is an upgrade from an existing version to a new one.
# - Similarly, the arguments to a %post are 1 and 2 for a new installation and upgrade, respectively. 
#   (Again, %pre and %post aren't executed during an uninstallation.)
# - If the first argument to %preun and %postun is 1, the action is an upgrade.
# - If the first argument to %preun and %postun is 0, the action is uninstallation.

%post
chown root:root %{install_sbin_dir}/%{mgr_real_name}
chmod 750 %{install_sbin_dir}/%{mgr_real_name}
chown root:root %{install_bin_dir}/%{remote_real_name}
chmod 755 %{install_bin_dir}/%{remote_real_name}
let docker_mgr_port_check=`egrep "Simple Remote Docker Manager" /etc/services | wc -l | awk '{print $1}'`
if [ ${docker_mgr_port_check} -eq 0 ]; then
    echo "%{xinetd_real_name}      %{docker_mgr_port}/tcp               # Simple Remote Docker Manager" >> /etc/services
fi
chkconfig xinetd on
chkconfig %{xinetd_real_name} on
service xinetd restart > /dev/null 2>&1
/bin/true
chkconfig %{docker_constart_real_name} on
/bin/true
service %{docker_constart_real_name} populate
/bin/true

%preun
if [ "${1}" = "0" ]; then
    chkconfig %{docker_constart_real_name} off > /dev/null 2>&1
fi
/bin/true

%postun
if [ "${1}" = "0" ]; then
    chkconfig %{xinetd_real_name} off > /dev/null 2>&1
    /bin/true
    let docker_mgr_port_check=`egrep "Simple Remote Docker Manager" /etc/services | wc -l | awk '{print $1}'`
    if [ ${docker_mgr_port_check} -gt 0 ]; then
        cp -p /etc/services /tmp/services.$$
        egrep -v "Simple Remote Docker Manager" /tmp/services.$$ > /etc/services
        rm -f /tmp/services.$$
    fi
    service xinetd restart > /dev/null 2>&1
fi
/bin/true

%files -f /tmp/MANIFEST.%{name}

%changelog
%define today %( date +%a" "%b" "%d" "%Y )
* %{today} %{rpm_author} <%{rpm_author_email}>
- built version %{version} for %{distro_id} %{distro_ver}

