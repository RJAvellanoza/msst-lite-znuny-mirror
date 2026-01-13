# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AdminLicense;

use strict;
use warnings;
use JSON;
use Crypt::CBC;
use Crypt::Rijndael;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject         = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $AdminLicenseObject = $Kernel::OM->Get('Kernel::System::License');

    # ------------------------------------------------------------ #
    # add
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Add' ) {
        my %GetParam;
        $GetParam{Name} = $ParamObject->GetParam( Param => 'Name' );
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Add',
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my @NewIDs = $ParamObject->GetArray( Param => 'IDs' );
        my ( %GetParam, %Errors );

        # get attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );

        my $key = "\xFC\xFC\x77\x6E\x08\xE2\x88\xB9\x3C\xCB\x2E\x14\x3E\xAC\x48\x3B"
        . "\x7F\xC1\xE8\xD4\xE2\x65\x87\x30\xCA\x69\x16\x0E\x12\x2B\x09\xD0";

        # --- Try with 16 null-byte IV (common default) ---
        my $iv  = "\x00" x 16;

        # --- Create AES cipher ---
        my $cipher = Crypt::CBC->new(
            -cipher      => 'Crypt::Rijndael',
            -key         => $key,
            -iv          => $iv,
            -literal_key => 1,
            -header      => 'none',
            -keysize     => 32,
        );

        # --- Decrypt content ---
        my $plaintext = $cipher->decrypt($UploadStuff{Content});

        # --- Strip out binary prefix before JSON (up to the first '{' character) ---
        $plaintext =~ s/^[^\{]*//;  # Remove everything before the first '{'

        # check needed data
        if ( !%UploadStuff ) {
            $Errors{FileUploadInvalid} = 'ServerError';
        }
        my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');
        # $GetParam{Content} = $JSONObject->Encode(
        #     Data => $plaintext,
        # );
        $GetParam{Content} = $plaintext;
        $GetParam{ContentType} = 'application/json';
        $GetParam{Filename} = 'JSON.json';
        
        # if no errors occurred
        if ( !%Errors ) {

            # add state
            my $AdminLicenseID = $AdminLicenseObject->AdminLicenseAdd(
                %GetParam,
                UserID => $Self->{UserID},
            );
            if ($AdminLicenseID) {
                return $LayoutObject->Redirect(
                    OP => "Action=AdminLicense",
                );
            }
        }

        # something has gone wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => 'Error' );
        $Self->_Edit(
            Action => 'Add',
            Errors => \%Errors,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # download action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Download' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $ID = $ParamObject->GetParam( Param => 'ID' );

        my %Data = $AdminLicenseObject->AdminLicenseGet(
            ID => $ID,
        );
        if ( !%Data ) {
            return $LayoutObject->ErrorScreen();
        }

        return $LayoutObject->Attachment(
            %Data,
            Type => 'attachment',
        );
    }

    # ------------------------------------------------------------
    # overview
    # ------------------------------------------------------------
    else {
        $Self->_Overview();
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminLicense',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

}

sub _Edit {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $LayoutObject->Block(
        Name => 'ActionList',
    );
    $LayoutObject->Block(
        Name => 'ActionOverview',
    );

    # add class for validation
    if ( $Param{Action} eq 'Add' ) {
        $Param{ValidateContent} = "Validate_Required";
    }

    $LayoutObject->Block(
        Name => 'OverviewUpdate',
        Data => {
            %Param
        },
    );

    return 1;
}

sub _Overview {
    my ( $Self, %Param ) = @_;

    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $AdminLicenseObject = $Kernel::OM->Get('Kernel::System::License');

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );
    $LayoutObject->Block(
        Name => 'ActionList',
    );
    $LayoutObject->Block(
        Name => 'ActionAdd',
    );
    $LayoutObject->Block(
        Name => 'Filter',
    );
    $LayoutObject->Block(
        Name => 'OverviewResult',
        Data => \%Param,
    );
    my %List = $AdminLicenseObject->AdminLicenseList(
        UserID => 1,
    );
    if (%List) {
        $LayoutObject->Block(
                Name => 'OverviewResultRow',
                Data => {
                    %List,
                },
            );
    }
    else {
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );
    }
    return 1;
        
}

1;
