# Mac mounting trick

For MAC you can mount root file system as a folder on root to have same paths as in a docker container.

1. To do that copy synthetic.cnf file to /etc folder. ```cp synthetic.conf /etc```
2. Reboot mac
3. Check if you have ```/host_mnt``` folder. It should point to root.

Happy hunting. 
