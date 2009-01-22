use strict;
use inc::Module::Install;
name 'POE-Component-Pluggable';
author 'Chris Williams <chris@bingosnet.co.uk>';
license 'perl';
version_from 'lib/POE/Component/Pluggable.pm';
abstract_from 'lib/POE/Component/Pluggable.pm';
build_requires 'Test::More' => 0.47;
perl_version '5.006';
eval "use Scalar::Util qw(weaken);";
if ( $@ ) {
   unless ( can_cc() ) {
	print <<NOTICE;

\a--------------------------------------------------------------
Hi,

Sorry about this but we require weak references by using 
Scalar::Util::weaken.

You don't appear to have a version of Scalar::Util installed
that supports weaken and your don't have a working compiler
available so that we can install a version of Scalar::Util
that does support weaken.

Giving up.
--------------------------------------------------------------

NOTICE
       exit 0;
   }
   requires 'Scalar::Util' => 1.19;
}
requires 'POE' => 1.0002;
WriteAll();
