# --
# Copyright (C) 2024 MSST
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::MSSTLiteIncidentAPI;

use strict;
use warnings;

sub CreateIncidentAPIWebservice {
    my (%Param) = @_;

    # Get needed objects
    my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');
    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    # Check if webservice already exists
    my $ExistingWebservice = $WebserviceObject->WebserviceGet(
        Name => 'IncidentAPI',
    );

    # Delete existing webservice if it exists, then recreate it
    if ($ExistingWebservice && $ExistingWebservice->{ID}) {
        my $Success = $WebserviceObject->WebserviceDelete(
            ID     => $ExistingWebservice->{ID},
            UserID => 1,
        );
        
        if ($Success) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => 'MSSTLiteIncidentAPI: Deleted existing IncidentAPI webservice',
            );
        }
    }

    # Define webservice configuration
    my $WebserviceConfig = {
        Debugger => {
            DebugThreshold => 'debug',
            TestMode => '0',
        },
        Description => 'REST API for Incident Operations - Create, Read, Update, Search incidents via API',
        FrameworkVersion => '6.5.15',
        ID => 0,
        Name => 'IncidentAPI',
        NameSpace => 'http://www.znuny.org/IncidentAPI/1.0',
        Provider => {
            ErrorHandling => {},
            ErrorHandlingPriority => [],
            Operation => {
                SessionCreate => {
                    Description => 'Creates a Session',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Session::SessionCreate',
                },
                SessionGet => {
                    Description => 'Retrieves a Session data',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Session::SessionGet',
                },
                SessionRemove => {
                    Description => 'Removes a Session',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Session::SessionRemove',
                },
                IncidentCreate => {
                    Description => 'Creates an Incident',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Incident::IncidentCreate',
                },
                IncidentGet => {
                    Description => 'Retrieves Incident data',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Incident::IncidentGet',
                },
                IncidentSearch => {
                    Description => 'Search for Incidents',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Incident::IncidentSearch',
                },
                IncidentUpdate => {
                    Description => 'Updates an Incident',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Incident::IncidentUpdate',
                },
                IncidentHistoryGet => {
                    Description => 'Get Incident History',
                    IncludeTicketData => '0',
                    MappingInbound => {},
                    MappingOutbound => {},
                    Type => 'Incident::IncidentHistoryGet',
                },
            },
            Transport => {
                Config => {
                    AuthModule => 'Kernel::System::Auth',
                    'AuthModule::User' => 1,
                    BasicAuth => 1,
                    Realm => 'Znuny REST API',
                    AdditionalHeaders => undef,
                    KeepAlive => '',
                    MaxLength => '52428800',
                    RouteOperationMapping => {
                        SessionCreate => {
                            RequestMethod => ['POST'],
                            Route => '/Session',
                        },
                        SessionGet => {
                            RequestMethod => ['GET', 'POST'],
                            Route => '/Session/:SessionID',
                        },
                        SessionRemove => {
                            RequestMethod => ['DELETE', 'POST'],
                            Route => '/Session/:SessionID',
                        },
                        IncidentCreate => {
                            RequestMethod => ['POST'],
                            Route => '/Incident',
                        },
                        IncidentGet => {
                            RequestMethod => ['GET', 'POST'],
                            Route => '/Incident/:IncidentID',
                        },
                        IncidentSearch => {
                            RequestMethod => ['GET', 'POST'],
                            Route => '/IncidentSearch',
                        },
                        IncidentUpdate => {
                            RequestMethod => ['PATCH', 'POST'],
                            Route => '/Incident/:IncidentID',
                        },
                        IncidentHistoryGet => {
                            RequestMethod => ['GET', 'POST'],
                            Route => '/IncidentHistory/:IncidentID',
                        },
                    },
                },
                Type => 'HTTP::REST',
            },
        },
        Requester => {
            ErrorHandling => {},
            ErrorHandlingPriority => [],
            Invoker => {},
            Transport => {
                Config => {},
                Type => '',
            },
        },
        RemoteSystem => '',
        Valid => 1,
        ValidID => 1,
    };

    # Add webservice
    my $WebserviceID = $WebserviceObject->WebserviceAdd(
        Name    => 'IncidentAPI',
        Config  => $WebserviceConfig,
        ValidID => 1,
        UserID  => 1,
    );

    if ($WebserviceID) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => 'MSSTLiteIncidentAPI: Successfully created IncidentAPI webservice with ID ' . $WebserviceID,
        );
        return 1;
    } else {
        $LogObject->Log(
            Priority => 'error',
            Message  => 'MSSTLiteIncidentAPI: Failed to create IncidentAPI webservice',
        );
        return 0;
    }
}

1;