#!/usr/bin/perl
# IBM(c) 2021 EPL license http://www.eclipse.org/legal/epl-v10.html
# 
# This module extends XML::Simple class.
#
# For versions of XML::Simple class which implement new_xml_parser():
# Overwrite XML::Simple::new_xml_parser() to pass parser options
# directly to the XML::Parser. The passing of parser options with
# XML::Simple::XMLin() has been depricated.
# 
#
# For older versions of XML::Simple class which do not implement new_xml_parser():
# Overwrite XML::Simple::build_tree_xml_parser() to pass parser options
# directly to the XML::Parser. The passing of parser options with
# XML::Simple::XMLin() has been depricated.
#
package xCAT::XML;
use XML::Simple;
use xCAT::MsgUtils;
use Carp;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';
use parent 'XML::Simple';

sub build_tree_xml_parser {
  my $self     = shift;
  my $filename = shift;
  my $string   = shift;

  # Check if parent class XML::Simple has implemented new_xml_parser(), 
  # if it has, just call XML::Simple::build_tree_xml_parser() from parent
  # and it in turn will call new_xml_parser() overwritten by this module.
  #
  # If parent class XML::Simple does not have new_xml_parser() implemented, 
  # fall through and execute the build_tree_xml_parser() overwritten
  # by this module.
  #
  if (exists &{XML::Simple::new_xml_parser}) {
      return $self->SUPER::build_tree_xml_parser($filename, $string);
  }

  eval {
    local($^W) = 0;      # Suppress warning from Expat.pm re File::Spec::load()
    require XML::Parser; # We didn't need it until now
  };
  if($@) {
    croak "XMLin() requires either XML::SAX or XML::Parser";
  }

  if($self->{opt}->{nsexpand}) {
    carp "'nsexpand' option requires XML::SAX";
  }
 
  my $xp = XML::Parser->new(Style => 'Tree',
                             [ load_ext_dtd => 0,
                               ext_ent_handler => undef,
                               no_network => 1,
                               expand_entities => 0,
                             ]);
  my($tree);
  if($filename) {
      # $tree = $xp->parsefile($filename);  # Changed due to prob w/mod_perl
      open(my $xfh, '<', $filename) || croak qq($filename - $!);
    $tree = $xp->parse($xfh);
  }
  else {
    $tree = $xp->parse($$string);
  }
 
  return($tree);
}

sub new_xml_parser {
  my($self) = @_;
  my $xp = XML::Parser->new(Style => 'Tree', 
                             [ load_ext_dtd => 0,
                               ext_ent_handler => undef,
                               no_network => 1,
                               expand_entities => 0,
                             ]);
  $xp->setHandlers(ExternEnt => sub {return $_[2]});
  return $xp;
}
1;
