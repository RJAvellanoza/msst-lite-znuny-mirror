package Kernel::Modules::AdminTicketPrefix;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
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

    # Store last entity screen.
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenEntity',
        Value     => $Self->{RequestedURL},
    );

    my $LayoutObject   = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TicketPrefixObject = $Kernel::OM->Get('Kernel::System::TicketPrefix');

   
    if ( $Self->{Subaction} eq 'InitialCounter' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck(); 
        my $InitialCounter =  $ParamObject->GetParam( Param => 'InitialCounter' ) || '';
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');        

        if ($InitialCounter) {
        	my $Count = $TicketObject->TicketSearch(
                TicketNumber => '*',                
                Result       => 'COUNT',              
                UserID       => $Self->{UserID},
            );
           

            if ($Count) {
                $Self->_Overview();
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => Translatable('Cannot Set Ticket Initial Counter as system has tickets already.') );
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminTicketPrefix',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }else{
            	my $InitialCounterObject = $Kernel::OM->Get('Kernel::System::InitialCounter');
            	my $Success = $InitialCounterObject->InitialCounterAdd(UserID => $Self->{UserID}, Counter => $InitialCounter );

            	if ($Success) {
                    # Update MinCounterSize to 10 to ensure proper padding
                    my %MinCountSetting = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingGet(
                        Name => 'Ticket::NumberGenerator::MinCounterSize',
                    );
                    $MinCountSetting{EffectiveValue} = 10;

                    my %MinCountResult = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingUpdate(
                        Name                   => 'Ticket::NumberGenerator::MinCounterSize',           
                        EffectiveValue         => 10,    
                        UserID                 => 1,                            
                    );
                    my $MinCountExclusiveLockGUID = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingLock(
                        Name   => $MinCountSetting{Name},
                        Force  => 1,
                        UserID => 1
                    );
                    $MinCountSetting{ExclusiveLockGUID} = $MinCountExclusiveLockGUID;

                    my %MinCountUpdateSuccess = $Kernel::OM->Get('Kernel::System::SysConfig')->SettingUpdate(
                        %MinCountSetting,
                        UserID => 1,
                    );
                    $Kernel::OM->Get('Kernel::System::SysConfig')->ConfigurationDeploy(
                        Comments      => "Min Counter size changed",
                        UserID        => 1,
                        Force         => 1,
                    );
                    
                    # Clear cache to ensure the new initial counter takes effect
                    $Kernel::OM->Get('Kernel::System::Cache')->CleanUp();

            		$Self->_Overview();
	                my $Output = $LayoutObject->Header();
	                $Output .= $LayoutObject->NavigationBar();
	                $Output .= $LayoutObject->Notify( Info => Translatable('InitialCounter Updated!') );
	                $Output .= $LayoutObject->Output(
	                    TemplateFile => 'AdminTicketPrefix',
	                    Data         => \%Param,
	                );
	                $Output .= $LayoutObject->Footer();
                	return $Output;
            	}            
                
            }
        }else{

        	$Self->_Overview();
	        my $Output = $LayoutObject->Header();
	        $Output .= $LayoutObject->NavigationBar();
	        $Output .= $LayoutObject->Notify( Info => Translatable('InitialCounter Updated!') );
	        $Output .= $LayoutObject->Output(
	            TemplateFile => 'AdminTicketPrefix',
	            Data         => \%Param,
	        );
	        $Output .= $LayoutObject->Footer();
	    	return $Output;
        }      
    }
    elsif ( $Self->{Subaction} eq 'Change' ) {
        my %GetParam = ();
        $GetParam{PrefixID} = $ParamObject->GetParam( Param => 'PrefixID' ) || '';
        my %PrefixData = $TicketPrefixObject->PrefixGet(
            PrefixID =>  $GetParam{PrefixID},
        );
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        

        $Self->_Edit(
            Action => 'Change',
            %PrefixData,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminTicketPrefix',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # change action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ChangeAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my ( %GetParam, %Errors );

        # get params
        for my $Parameter (qw(PrefixID TypeID Prefix ValidID)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # check needed data
        for my $Needed (qw(PrefixID TypeID Prefix ValidID)) {
            if ( !$GetParam{$Needed} ) {
                $Errors{ $Needed . 'Invalid' } = 'ServerError';
            }
        }    
        # if no errors occurred
        if ( !%Errors ) {   
           
            # update NewPrefix
            my $Update = $TicketPrefixObject->PrefixUpdate(
                %GetParam,
                UserID => $Self->{UserID}
            );

            if ($Update) { 

                $Self->_Overview();
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => Translatable('Prefix Updated!') );
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminTicketPrefix',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
                # return $LayoutObject->Redirect( OP => "Action=$Self->{Action}" );
            }
        }

        # something has gone wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => Translatable('Error') );
        $Self->_Edit(
            Action => 'Change',
            Errors => \%Errors,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminTicketPrefix',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Add' ) {
        my %GetParam = ();
        $GetParam{PriorityID} = $ParamObject->GetParam( Param => 'PriorityID' ) || '';
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Add',
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminTicketPrefix',
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

        my ( %GetParam, %Errors );

        # get params
        for my $Parameter (qw(TypeID Prefix ValidID)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # check needed data
        for my $Needed (qw(TypeID Prefix ValidID)) {
            if ( !$GetParam{$Needed} ) {
                $Errors{ $Needed . 'Invalid' } = 'ServerError';
            }
        }

        # if no errors occurred
        if ( !%Errors ) {

            my $Dup = $TicketPrefixObject->PrefixDuplicate(TypeID => $GetParam{TypeID});
            if ($Dup) {
                $Self->_Overview();
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => Translatable('Duplicate Prefix for Type!') );
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminTicketPrefix',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }
            my $NewPrefix = $TicketPrefixObject->PrefixAdd(
                %GetParam,
                UserID => $Self->{UserID},
            );

            if ($NewPrefix) {
                $Self->_Overview();
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => Translatable('Prefix Configured!') );
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminTicketPrefix',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }
        }

        # something has gone wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => Translatable('Error') );
        $Self->_Edit(
            Action => 'Add',
            Errors => \%Errors,
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminTicketPrefix',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------
    # overview
    # ------------------------------------------------------------
    else {
        $Self->_Overview();
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminTicketPrefix',
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

    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block( Name => 'ActionOverview' );

    # get valid list
    my %ValidList        = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();
    my %ValidListReverse = reverse %ValidList;

    $Param{ValidOptionStrg} = $LayoutObject->BuildSelection(
        Data       => \%ValidList,
        Name       => 'ValidID',
        SelectedID => $Param{ValidID} || $ValidListReverse{valid},
        Class      => 'Modernize Validate_Required ' . ( $Param{Errors}->{'ValidIDInvalid'} || '' ),
    );

    # get valid list
    my %TypeList        = $Kernel::OM->Get('Kernel::System::Type')->TypeList();

    $Param{TypeOptionStrg} = $LayoutObject->BuildSelection(
        Data       => \%TypeList,
        Name       => 'TypeID',
        SelectedID => $Param{TypeID},
        Class      => 'Modernize Validate_Required ' . ( $Param{Errors}->{'ValidIDInvalid'} || '' ),
    );

    $LayoutObject->Block(
        Name => 'OverviewUpdate',
        Data => {
            %Param,
            %{ $Param{Errors} },
        },
    );


    return 1;
}

sub _Overview {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $InitialCounterObject = $Kernel::OM->Get('Kernel::System::InitialCounter');
    $Param{InitialCounter} =  $InitialCounterObject->InitialCounterGet();

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block( Name => 'ActionAdd' );
    $LayoutObject->Block( 
        Name => 'Filter',
        Data => {InitialCounter => $Param{InitialCounter}},
     );

    $LayoutObject->Block(
        Name => 'OverviewResult',
        Data => \%Param,
    );

    my $TicketPrefixObject = $Kernel::OM->Get('Kernel::System::TicketPrefix');

    my %PrefixList = $TicketPrefixObject->PrefixList(
    );

    if (%PrefixList) {

        # get valid list
        my %ValidList = $Kernel::OM->Get('Kernel::System::Valid')->ValidList();

        for my $PrefixID ( sort { $a <=> $b } keys %PrefixList ) {

            # get Prefix data
            my %PrefixData = $TicketPrefixObject->PrefixGet(
                PrefixID    => $PrefixID,
            );

            $LayoutObject->Block(
                Name => 'OverviewResultRow',
                Data => {
                    %PrefixData,
                    PrefixID    => $PrefixID,
                    Valid      => $ValidList{ $PrefixData{ValidID} },
                },
            );
        }
    }

    # otherwise a no data found msg is displayed
    else {
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );
    }
    return 1;
}

1;
