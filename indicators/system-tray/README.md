# Wingpanel Ayatana-Compatibility Indicator (Community Version)
<h1>Description:</h1>
Keep compatibility with ubuntu/unity indicators on Elementary OS wingpanel.
If you want to install applications with indicators like weather forecast, redshift... this plug-in 
let these indicators appear in your panel. 

<p align="center"><img src="screenshot.png"/> </p>

<h1>Easy Install (user only)</h1>
1. Download the deb file (zip) and launch install<br/>

<h2>Parameters for Pantheon (eos)</h2>
2. You need to add Pantheon to the list of desktops abled to work with indicators:<br/>
<ul>
<li>With autostart (thanks to JMoerman) </li>
just add /usr/lib/x86_64-linux-gnu/indicator-application/indicator-application-service as custom command to the auto start applications in the system settings.
System settings -> "Applications" -> "Startup" -> "Add Startup App…" -> "Type in a custom command".
No need for manually editing files using root and no risks of .desktop files being overwritten.
<br/>

<li>With the terminal (thanks to ankurk91) </li>
Open Terminal and run the following commands.
<pre>mkdir -p ~/.config/autostart
cp /etc/xdg/autostart/indicator-application.desktop ~/.config/autostart/
sed -i 's/^OnlyShowIn.*/OnlyShowIn=Unity;GNOME;Pantheon;/' ~/.config/autostart/indicator-application.desktop
</pre><br/>

<li>Editing files (more risks)</li>
<pre>sudo nano /etc/xdg/autostart/indicator-application.desktop</pre>
Search the parameter: OnlyShowIn= and add "Pantheon" at the end of the line : 
<pre>OnlyShowIn=Unity;GNOME;Pantheon;</pre>
Save your changes (Ctrl+X to quit + Y(es) save the changes + Enter to valid the filename).<br/>
</ul>

3.<b>reboot</b>.

<h1>Build and install (developer)</h1>
<h2>Dependencies</h2>

1. You'll need the following dependencies to build :

<pre>sudo apt-get install libglib2.0-dev libgranite-dev libindicator3-dev 
sudo apt-get install libwingpanel-2.0-dev valac gcc meson </pre/>

<h2>Build with meson</h2>

2. Download the last release (zip) and extract files<br/>
3. Open a Terminal in the extracted folder, build your application with meson and install it with ninja:<br/>

<pre>meson build --prefix=/usr
cd build
ninja
sudo ninja install
</pre>

4. Follow step 2 from easy install (parameters) and reboot.

<h2>uninstall</h2>
Open a terminal in the build folder.
<pre>sudo ninja uninstall
killall wingpanel
</pre>
