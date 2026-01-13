# Incident Module Navigation Issues

## Summary
Attempting to rename/replace the Tickets menu with an Incidents menu has revealed multiple fundamental issues with how Znuny's navigation system works.

## Core Issues

### 1. Navigation Highlighting Problem
- **Issue**: When clicking "Create Incident" from the Incidents menu, the system highlights the Tickets menu instead
- **Cause**: Navigation highlighting is based on the active module/action, not the menu item clicked
- **Details**: 
  - Incident menu items call Ticket actions (e.g., `Action=AgentTicketPhone`)
  - These actions are registered with `NavBarName="Ticket"`
  - System automatically highlights the NavBar that owns the current action

### 2. Package Installer File Management
- **Issue**: Removing files from the package doesn't remove them from the live system
- **Impact**: Old configuration files remain active even after being removed from the package
- **Examples**:
  - `/opt/znuny-6.5.15/Kernel/Config/Files/XML/HideTicketsMenu.xml`
  - `/opt/znuny-6.5.15/Kernel/Config/Files/XML/OverrideTicketsMenu.xml`
  - These orphaned files continue to affect the system

### 3. XML Configuration Override Limitations
- **Issue**: Cannot cleanly "rename" existing navigation entries
- **Details**:
  - Can disable entries (`Valid="0"`)
  - Can add new entries
  - Cannot modify existing entries from other packages/core
  - Multiple XML files defining same settings create conflicts

### 4. Module-Navigation Dependency
- **Issue**: Navigation entries depend on their associated modules
- **Impact**: 
  - Disabling Ticket modules breaks Incident menu functionality
  - Cannot use Ticket actions without Ticket modules being active
  - Creates circular dependency when trying to replace Tickets with Incidents

### 5. Configuration Load Order Issues
- **Issue**: XML configuration files load alphabetically
- **Problems encountered**:
  - `HideTicketsMenu.xml` loaded before `Ticket.xml` (from core)
  - Attempts to disable things that haven't been loaded yet
  - Required multiple renaming attempts (ZZZHideTicketsMenu.xml, etc.)

### 6. NavBar Grouping Confusion
- **Issue**: Navigation items with same NavBar value get grouped together
- **Attempted solution**: Changed NavBar from "Ticket" to "Incident"
- **Result**: Broke the connection between menu items and their actions

### 7. Frontend::Navigation Key Conflicts
- **Issue**: Same navigation keys used by both core and custom modules
- **Example**: 
  - Core uses `AgentTicketPhone###002-Ticket`
  - We tried `AgentTicketPhone###001-Incidents`
  - Both try to define navigation for the same action

### 8. Incomplete Navigation Hiding
- **Issue**: Multiple navigation entries exist for Ticket menu
- **Found entries**:
  - `###002-Ticket` (main entries)
  - `###001-Framework` (some items)
  - `###002-ProcessManagement` (process tickets)
  - Different keys for different actions
- **Result**: Hiding some entries but missing others

## Technical Constraints

1. **Cannot modify core files** - Must work through package system
2. **Cannot override module registrations** - Only navigation entries
3. **Action-NavBar binding is hardcoded** - Cannot change which NavBar an action belongs to
4. **No "alias" mechanism** - Cannot make one action pretend to be another for navigation purposes

## Current State

- Two separate menus exist: "Tickets" and "Incidents"
- Incidents menu items work but highlight Tickets menu when clicked
- Users see both menus, causing confusion
- Functional but poor user experience

## Failed Approaches

1. **XML Override** - Tried to override Ticket navigation with Incident navigation
2. **Disable and Replace** - Disabled Ticket navigation, added Incident navigation
3. **NavBar Separation** - Changed NavBar to "Incident" but broke functionality
4. **Hide Ticket Modules** - Broke all ticket functionality
5. **Perl Config Override** - Created more conflicts than solutions

## Root Cause

The fundamental issue is architectural: Znuny's navigation system tightly couples:
- Module registration (the action)
- Navigation registration (the menu item)  
- NavBar assignment (the highlighting)

These cannot be separated or overridden independently, making it impossible to cleanly "rename" a menu while keeping its functionality.