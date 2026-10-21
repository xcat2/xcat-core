##############
freebsdimage.5
##############


****
NAME
****


\ **freebsdimage**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **freebsdimage Attributes:**\   \ *imagename*\ , \ *template*\ , \ *pkgdir*\ , \ *partitionfile*\ , \ *comments*\ , \ *disable*\ , \ *imageversion*\ , \ *bootdir*\ , \ *pkglist*\ , \ *otherpkgdir*\ , \ *otherpkglist*\


***********
DESCRIPTION
***********


Information about a FreeBSD image for scripted stateful installation.


************************
freebsdimage Attributes:
************************



\ **imagename**\

 The name of this xCAT OS image definition.



\ **template**\

 The absolute path of the FreeBSD installation configuration template. The template contains key=value settings.



\ **pkgdir**\

 For an unset imageversion or version 1, the absolute path of the imported xCAT mfsBSD bundle. For imageversion=2, the absolute path of one imported base repository role. FreeBSD amd64 media uses the xCAT architecture x86_64.



\ **partitionfile**\

 The absolute path of the FreeBSD storage policy. It selects the OS disks explicitly and can contain [pool NAME] sections for dedicated data pools and [dataset POOL/PATH] sections for OS and data filesystems. #NODE# expands to the node name.



\ **comments**\

 Any user-written notes.



\ **disable**\

 Set to 'yes' or '1' to comment out this row.



\ **imageversion**\

 The FreeBSD image definition version. An unset value or 1 uses the legacy mfsBSD bundle. Version 2 separates the boot artifact and repositories.



\ **bootdir**\

 For imageversion=2, the absolute path of the imported xCAT mfsBSD boot artifact. Version 2 installation requires a compatible pkgbase runtime.



\ **pkglist**\

 For imageversion=2, comma-separated absolute paths of files that select base components. Importing a repository does not select packages.



\ **otherpkgdir**\

 For imageversion=2, comma-separated absolute paths of imported DVD application or supplemental repository roles, in native resolver priority order.



\ **otherpkglist**\

 For imageversion=2, comma-separated absolute paths of application package list files. Importing a repository does not select packages.




********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\
