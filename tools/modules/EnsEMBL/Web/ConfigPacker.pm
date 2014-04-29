=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package EnsEMBL::Web::ConfigPacker;

use strict;
use warnings;

use previous qw(munge_config_tree munge_config_tree_multi);

sub munge_config_tree {
  my $self = shift;
  $self->PREV::munge_config_tree(@_);
  $self->_configure_blast;
}

sub munge_config_tree_multi {
  my $self = shift;
  $self->PREV::munge_config_tree_multi(@_);
  $self->_configure_blast_multi;
}

sub _configure_blast {
  my $self        = shift;
  my $tree        = $self->tree;
  my $multi_tree  = $self->full_tree->{'MULTI'};
  my $species     = $self->species;
  my $blast_types = $multi_tree->{'ENSEMBL_BLAST_TYPES'};

  while (my ($blast_type, $blast_label) = each %$blast_types) { #NCBIBLAST, BLAT, WUBLAST etc
    next if $blast_type eq 'ORDER';

    my $dbtype_to_sourcetype = {};

    my $source_types = $multi_tree->{'ENSEMBL_BLAST_DATASOURCES_'.$blast_type} || {};
    while (my ($source_type, $source_type_details) = each %$source_types) { #LATESTGP, CDNA_ALL, PEP_ALL etc
      next if $source_type eq 'ORDER';

      $source_type_details =~ /^([^\s]+)/;

      my $db_type = $1;
      my $method  = sprintf '_get_%s_source_file', $blast_type;

      ## TODO - before adding this entry, check if this species actually has this source

      $dbtype_to_sourcetype->{$db_type}{$source_type} = $self->$method($source_type);
    }

    my $search_types = $multi_tree->{'ENSEMBL_BLAST_METHODS_'.$blast_type} || {};
    while (my ($search_type, $search_type_details) = each %$search_types) { #BLASTN, BLASTP, TBLASTX etc
      next if $search_type eq 'ORDER';

      my ($query_type, $db_type, $program) = @$search_type_details;

      $tree->{'ENSEMBL_BLAST_CONFIGS'}{$query_type}{$db_type}{"${blast_type}_${search_type}"} = { %{$dbtype_to_sourcetype->{$db_type} || {}} };
    }
  }
}

sub _configure_blast_multi {
  my $self                  = shift;
  my $multi_tree            = $self->full_tree->{'MULTI'};
  my $blast_types           = {%{$multi_tree->{'ENSEMBL_BLAST_TYPES'} || {}}};
  my $blast_types_ordered   = [ map { delete $blast_types->{$_} ? [ $_ ] : () } @{delete $blast_types->{'ORDER'} || []}, sort keys %$blast_types ];
  my $search_types_ordered  = [];
  my $all_sources           = {};
  my $all_sources_order     = [];

  foreach my $blast_type (@$blast_types_ordered) {

    my $sources       = {};
    my $source_types  = $multi_tree->{'ENSEMBL_BLAST_DATASOURCES_'.$blast_type->[0]} || {};

    foreach my $source_type (@{delete $source_types->{'ORDER'} || []}, sort keys %$source_types) { #LATESTGP, CDNA_ALL, PEP_ALL etc
      my $source_type_details = delete $source_types->{$source_type} or next;
         $source_type_details =~ /^([^\s]+)\s+(.+)$/;

      my $db_type = $1;
      my $label   = $2;
      push @{$sources->{$db_type}}, $source_type;
      push @$all_sources_order, $source_type;
      $all_sources->{$source_type} = $label;
    }

    my $search_types = {%{$multi_tree->{'ENSEMBL_BLAST_METHODS_'.$blast_type->[0]}}};
    for (@{delete $search_types->{'ORDER'} || []}, sort keys %$search_types) {
      if ($search_types->{$_}) {
        push @$search_types_ordered, {
          'search_type' => "$blast_type->[0]_$_",
          'query_type'  => $search_types->{$_}[0],
          'db_type'     => $search_types->{$_}[1],
          'program'     => $search_types->{$_}[2],
          'sources'     => [ @{$sources->{$search_types->{$_}[1]}} ] # clone the array to avoid future accidental manipulation
        };
        delete $search_types->{$_};
      }
    }
  }
  $multi_tree->{'ENSEMBL_BLAST_DATASOURCES_ORDER'}  = $all_sources_order;
  $multi_tree->{'ENSEMBL_BLAST_DATASOURCES'}        = $all_sources;
  $multi_tree->{'ENSEMBL_BLAST_CONFIGS'}            = $search_types_ordered;
}

sub _get_NCBIBLAST_source_file {
  my ($self, $source_type) = @_;

  my $species   = $self->species;
  my $assembly  = $self->tree->{$species}{'ASSEMBLY_NAME'};
  my $db_tree   = $self->db_tree;

  (my $type     = lc $source_type) =~ s/_/\./;

  return sprintf '%s.%s.%s.%s.fa', $species, $assembly, $db_tree->{'DB_RELEASE_VERSION'} || $SiteDefs::ENSEMBL_VERSION, $type unless $type =~ /latestgp/;

  $type =~ s/latestgp(.*)/dna$1\.toplevel/;
  $type =~ s/.masked/_rm/;
  $type =~ s/.soft/_sm/;
 
  return sprintf '%s.%s.%s.%s.fa', $species, $assembly, $db_tree->{'REPEAT_MASK_DATE'} || $db_tree->{'DB_RELEASE_VERSION'}, $type;
}

sub _get_BLAT_source_file {
  my ($self, $source_type) = @_;
  return $self->tree->{'BLAT_DATASOURCES'}{$source_type};
}

1;
