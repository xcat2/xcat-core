Code Standard for Perl
======================

This document gives out a ``Code Standard`` for Perl programming in xCAT. All the Perl code which is checked in to xCAT code repository should follow this standard.

This document does not give the coding rules one by one, but give a piece of example code. You need to follow the example code strictly.

This standard referred to the Perl code style from perldoc: http://perldoc.perl.org/perlstyle.html

Tidy Your Code
--------------

Meanwhile, you are recommended to use following command line to tidy your code: ::

    perltidy -w -syn -g -opt -i=4 -nt -io -nbbc -kbl=2 -pscf=-c -aws \
        -pt=2 -bbc -nolc  <orig_code> -o <formatted_code>

How to install ``perltidy`` tool:

* **[RHEL]** ::

    yum install perltidy.noarch
    
* **[UBUNTU]** ::

    apt-get install perltidy

Code Standard Example:
----------------------

::

    #! /usr/bin/perl
    
    # This is a perl program example to demo the recommended
    # style to write perl code
    
    use strict;
    use warnings;
    
    #--------------------------------------------------------------------------------
    
    =head3   subroutine_example
        Descriptions:
            This a subroutine to demo how to write perl code
        Arguments:
            param1: The first parameter
            param2: The second parameter
            param3: The third parameter
        Returns:
            0 - success
            0 - fail
    =cut
    
    #--------------------------------------------------------------------------------
    sub subroutine_example {
        my ($param1, $param2, $param3) = @_;
    
        print "In the subroutine subroutine_example.\n";
    
        return 0;
    }
    
    
    # Declare variables
    my $a_local_scale;
    my @a_local_array;
    my %a_local_hash;
    
    $a_local_scale = 1;
    
    @a_local_array = ("a", "b", "c");
    
    %a_local_hash = (
        "v1" => 1,
        "v2" => 2,
        "v3" => 3,
    );
    
    # Demo how to check the key of hash
    if (%a_local_hash and
        defined($a_local_hash{v1}) and
        defined($a_local_hash{v2}) and
        defined($a_local_hash{v3})) {
    
        # Calculate the sum of values
        my $sum_of_values = $a_local_hash{v1}
          + $a_local_hash{v2}
          + $a_local_hash{v3};
    
        print "The sum of values: $sum_of_values.\n";
    }
    
    # Demo how to check whether the array is empty
    if (@a_local_array) {
        print "Has element in array: " . join(',', @a_local_array) . "\n";
    }
    elsif ($a_local_scale) {
        print "The value of a scale variable: $a_local_scale.\n";
    }
    else {
        # None of above
        print "Get into the default path.\n";
    }
    
    # Call the subroutine subroutine_example()
    subroutine_example($a_local_scale, \@a_local_array, %a_local_hash);
    
    exit 0;
