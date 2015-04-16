/**
 *  31 Dec 2013:   Dinesh M:   Created CRMGPS-4314, Merge Triggers on User
 *
 *  Summary:
 *  According to salesforce best practices, ideally there should be only one trigger on each object. 
 *  Currently there are four triggers on User, so we need to combine these triggers into single trigger on User.
 *
 *  We have below active triggers on User object in QA
 *  1.  T1C_SyncUserToEmployee (Before insert, after insert, after update, before update) 
 *  2.  MatchUserToEmployee  (After insert, after update)
 *  3.  ArchiveUserStatusUpdate (After update)
 *  4.  TeamSharing (After insert, after update, before insert, before update)  
**/

trigger UserTrigger on User (Before Insert, After Insert, Before Update, After Update) {
    
    /*TODO: Implement Trigger Switch*/
    Chatter_Settings__c dSwitch2 = Chatter_Settings__c.getInstance('Default');
    Trigger_Switch__c dSwitch = Trigger_Switch__c.getInstance();
    
    /***************T1C_SyncUserToEmployee Implementation***************/
    if(dSwitch == null || dSwitch.Is_T1C_SyncUserToEmployee_Trigger_On__c == false) {
        return;
    }
    
    UserServiceTierTriggerHandler ustriggerHandler=new UserServiceTierTriggerHandler(); //Handler instance : Jira CRMGPS-4297
    Map<String , String> userServiceTierMap = new Map<String , String>();  //Stores the mapping of user id to service tier : Jira CRMGPS-4297
    
    T1C_SyncUserAndEmployeeManager.syncUserToEmployee(trigger.new, trigger.oldMap, trigger.isUpdate, trigger.isBefore); 
    
    if(Trigger.isAfter){
        //T1C_GrpMbrshipManager.addUserToPublicGroup(trigger.newMap, trigger.oldMap, trigger.isUpdate);
        T1C_UserAFRPreferenceSyncManager.overrideAttributes(trigger.new, trigger.oldMap, trigger.isInsert);                 
        //++11/13/2013 : Mangesh Godse : Added code for Account voting indicator update on T1c_Employee : Jira : CRMGPS-4297
                    
        if(Trigger.isInsert){           
            for(User stUser : Trigger.new){             
                if(stUser.T1C_Preference_Service_Tier__c != null && stUser.T1C_Preference_Service_Tier__c != ''){           // trigger will fire if the field is not blank
                    userServiceTierMap.put(stUser.Id , stUser.T1C_Preference_Service_Tier__c );             // adding id and Service_Tier__c to the map                
                }                   
            }
        }else{          
            for(User stUser : Trigger.new){             
                if(Trigger.oldMap.get(stUser .Id).T1C_Preference_Service_Tier__c != stUser.T1C_Preference_Service_Tier__c){  // checking value Service_Tier__c tire has changed 
                    userServiceTierMap.put(stUser.Id , stUser.T1C_Preference_Service_Tier__c );               // adding id and Service_Tier__c value to a map
                }
            }
        }
                   
        //call handler to update the voting region on related T1c_Employee
        if(userServiceTierMap != null && userServiceTierMap.size()>0){
          ustriggerHandler.updateEmployeeServiceTier(userServiceTierMap);
        }
        //--11/13/2013 : Mangesh Godse : Added code for Account voting indicator update on T1c_Employee : Jira : CRMGPS-4297
    }else {      
        T1C_UserAFRPreferenceSyncManager.updateDisplayDirectLinePreference(trigger.new, trigger.oldMap, trigger.isInsert);
        // 01/16/2013 : set preferences values for users.
        T1C_UserPreferencesManager.setDefaultUserPreferences(trigger.new, trigger.isInsert);
    }
    
    /****************MatchUserToEmployee Implementation****************/
    if(trigger.isAfter && (trigger.isInsert || trigger.isUpdate)){
        if(!dSwitch.Is_MatchUserToEmployee_Trigger_On__c) {
            return;
        }
  
        if(system.isFuture()) {
            system.debug('-------future call will return');
            return;
        }
        
        List<Id> IdsOfUsersWithNewMSIDs = new List<Id>();
        for (User u : Trigger.new) {
            if (Trigger.isInsert) {
                IdsOfUsersWithNewMSIDs.add(u.Id);
            } else {
                if (u.MSID__c != Trigger.oldMap.get(u.Id).MSID__c) {
                    IdsOfUsersWithNewMSIDs.add(u.Id);
                }
            }
        }
        // call out to @future method, to avoid MIXED_DML_OPERATION exception when updating Employee__c records
        system.debug('-------class call');
        MatchUserToEmployee.matchUserToEmployee(IdsOfUsersWithNewMSIDs);    
    }   
    
    /****************ArchiveUserStatusUpdate Implementation****************/
    if(trigger.isAfter && trigger.isUpdate){
        
           
        if((!dSwitch2.Allow_Chatter_Posts_and_Comments__c) ) {
            //You cannot insert new Chatter Posts or Comments at this time.                 
            trigger.new[0].addError(dSwitch2.Error_Message__c);
            return;
        }               
         
        //Custom Setting to control trigger ON/OFF
        if(dSwitch2.Enable_Archiving__c == false || dSwitch.Is_ArchiveUserStatusUpdate_Trigger_On__c == false) {
            return;
        }
            
        //25 Oct 2013:  Dinesh M:   Fix for Future method cannot be called from a future or batch method 
        if(system.isFuture()) {
            return;
        }
            
        String SObjectTypeName = 'User';            
        ChatterArchiveManager.ArchiveFeedTracking_future(trigger.new[0].id,false,SObjectTypeName);          
    }
    
    /****************TeamSharing Implementation****************/
    if(!dSwitch.Is_TeamSharing_Trigger_On__c) {
       return;
    }
      
    // The users that have been processed - their current and also previous values if they are being updated
    List<User> oldUsers = Trigger.old;
    List<User> newUsers = Trigger.new;
    
    List<User> filterNew = new List<User>();
    List<User> filterOld = new List<User>();
    String powerUserId = '';
    String adminId = '';
        
    // Grab the user Ids of the power user and system administrator
    List<Profile> powerUser = [select Id, Name from Profile where name = 'Sales GPS | Power User' or name = 'System Administrator'];
                                                                                                                                                //'GPS | Power User' or name = 'System Administrator']; 09 March 2011
    if(powerUser!=null && powerUser.size()>0){
        for(Profile p:powerUser){   
            //if(p.Name=='GPS | Power User'){ 09 March 2011
            if(p.Name=='Sales GPS | Power User'){
                powerUserId=p.Id;
                System.debug('Power User Id: '+powerUserId);
            }
            if(p.Name=='System Administrator'){
                adminId=p.Id;
                System.debug('Power User Id: '+adminId);
            }
        }
    }       
        
    if(Trigger.isAfter){
        System.debug('Trigger After occured');
        Integer x=0;
        
        for(User filteredUser:newUsers){
            // Separate out the Standard users from the power users and system administrators              
            if(filteredUser.User_Type__c!=adminId && oldUsers==null){
                filterNew.add(filteredUser);
            }
            
            if(filteredUser.ProfileId!=adminId && oldUsers!=null && oldUsers[x].ProfileId!=adminId){
                filterNew.add(filteredUser);
                filterOld.add(oldUsers[x]);
            }
            x++;
        }   
        System.debug('Filter new: '+filterNew);
        System.debug('Filter old: '+filterOld);
    }
    
    if(filterNew.size()>0){
        System.debug('Filter New is Greater then 0 Records!');
        // The team share utils will do the heavy lifting in entitling the standard users to their team sharing entry
        TeamShareUtils teamShare = new TeamShareUtils(filterNew, filterOld); 
           
        if(Trigger.isInsert && Trigger.isAfter){
            System.debug('Create New User');
            teamShare.createUsers();    
        }
        
        if(Trigger.isUpdate && Trigger.isAfter){
            System.debug('Updating the User'); 
            teamShare.updateUsers();
        }
    }
            
    if(Trigger.isInsert && Trigger.isBefore){
        // Flag the power user or system administrator record for processing
        for(User usr:newUsers){
            if(usr.User_Type__c==powerUserId || usr.ProfileId==adminId){
                System.debug('Process this record(insert)');
                usr.Should_Be_Processed__c=true;    
            }
        }   
    }
    
    Integer i=0;
    
    if(Trigger.isUpdate && Trigger.isBefore){   
    // Flag the power user or system administrator record for processing
        for(User usrNew:newUsers){
            if(usrNew.isActive!=oldUsers[i].isActive || usrNew.User_Type__c!=oldUsers[i].User_Type__c || usrNew.UserRoleId!=oldUsers[i].UserRoleId){
                System.debug('New User Profile Id: '+usrNew.User_Type__c);
                System.debug('Old User Profile Id: '+oldUsers[i].User_Type__c);
                System.debug('Power User Id: '+powerUserId);
                
                if(usrNew.User_Type__c==powerUserId || oldUsers[i].User_Type__c==powerUserId || usrNew.User_Type__c==adminId || oldUsers[i].User_Type__c==adminId){
                    System.debug('Process this record(update)');
                    usrNew.Should_Be_Processed__c=true;
                }
            }
            i++;                
        }
    }
}