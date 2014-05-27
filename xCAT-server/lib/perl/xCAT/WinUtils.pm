# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html

#This module provides various functions and lookup tables specific to deployment of Microsoft windows
package xCAT::WinUtils;
use strict;

#the list of KMS client keys per technet that are supposed to be used when an enterpise has KMS set up..
#ms uniquely identifies the version and 'flavor', processor architecture does not factor in
#reference: http://technet.microsoft.com/en-us/library/jj612867.aspx
#fyi, hyper-v 2012 has no license key, it's a free product
our %kmskeymap = (
	"win8.professional" => "NG4HW-VH26C-733KW-K6F98-J8CK4",
	"win8.professional_n" => "XCVCF-2NXM9-723PB-MHCB7-2RYQQ",
	"win8.enterprise" => "32JNW-9KQ84-P47T8-D8GGY-CWCK7",
	"win8.enterprise_n" => "JMNMF-RHW7P-DMY6X-RF3DR-X2BQT",
    "win81.professional" => "GCRJD-8NW9H-F2CDX-CCM8D-9D6T9",
    "win81.professional_n" => "HMCNV-VVBFX-7HMBH-CTY9B-B4FXY",
	"win81.enterprise" => "MHF9N-XY6XB-WVXMC-BTDCT-MKKG7",
	"win81.enterprise_n" => "TT4HM-HN7YT-62K67-RGRQJ-JFFXW",
    "win2012r2.standard" => "D2N9P-3P6X9-2R39C-7RTCD-MDVJX",
    "win2012r2.datacenter" => "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9",
    "win2012r2.essentials" => "KNC87-3J2TX-XB4WP-VCPJV-M4FWM",
	"win2012.standard" => "XC9B7-NBPP2-83J2H-RHMBY-92BT4", #note that core and non-core share KMS key
	"win2012.datacenter" => "48HP8-DN98B-MYWDG-T2DCC-8W83P",
	"win7.professional" => "FJ82H-XT6CR-J8D7P-XQJJ2-GPDD4",
	"win7.professional_n" => "MRPKT-YTG23-K7D7T-X2JMM-QY7MG",
	"win7.professional_e" => "W82YF-2Q76Y-63HXB-FGJG9-GF7QX",
	"win7.enterprise" => "33PXH-7Y6KF-2VJC9-XBBR8-HVTHH",
	"win7.enterprise_n" => "YDRBP-3D83W-TY26F-D46B2-XCKRJ",
	"win7.enterprise_e" => "C29WB-22CC8-VJ326-GHFJW-H9DH4",
	"win2k8r2.standard" => "YC6KT-GKW9T-YTKYR-T4X34-R7VHC",
	"win2k8r2.enterprise" => "489J6-VHDMP-X63PK-3K798-CPX3Y",
	"win2k8r2.datacenter" => "74YFP-3QFB3-KQT8W-PMXWJ-7M648", #note, itanium had a different key, but we won't support that...
);
