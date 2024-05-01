public class SessionSyncFromOpportunity {

    //after insert
    public static void cloneNewOpp(List<Opportunity> newOpportunities) {
        List<Session__c> sessionsToInsert = new List<Session__c>();
        Map<Id, Session__c> oppIdToSessionMap = new Map<Id, Session__c>();

        for (Opportunity opp : newOpportunities) {
            Session__c newSession = new Session__c();
            // Only proceed if the RecordType exists
            if (copyFields(opp, newSession)) {
                sessionsToInsert.add(newSession);
                oppIdToSessionMap.put(opp.Id, newSession);
            } else {
                System.debug('Skipping clone for Opportunity with Id: ' + opp.Id);
            }
        }
    
        if (!sessionsToInsert.isEmpty()) {
            insert sessionsToInsert;
    
            // Update Opportunity records with the ID of the newly created Session__c records
            List<Opportunity> oppsToUpdate = new List<Opportunity>();
            for (Opportunity opp : newOpportunities) {
                Session__c clonedSession = oppIdToSessionMap.get(opp.Id);
                if (clonedSession.Id != null) {
                    Opportunity updatedOpp = new Opportunity(Id = opp.Id, Cloned_Session__c = clonedSession.Id);
                    oppsToUpdate.add(updatedOpp);
                }
            }
    
            if (!oppsToUpdate.isEmpty()) {
                update oppsToUpdate;
            }
        }
    }

    //after update
    public static void updateClonedOpp(Map<Id, Opportunity> newMap, Map<Id, Opportunity> oldMap) {
    
        logFieldChanges(newMap, oldMap);
    
        List<Session__c> sessionsToUpdate = new List<Session__c>();
        for (Opportunity newOpp : newMap.values()) {
    
            List<Session__c> sessionList = [SELECT Id FROM Session__c WHERE Related_Opportunity__c = :newOpp.Id LIMIT 1];
            if (!sessionList.isEmpty()) {
                Session__c existingSession = sessionList[0];
                System.debug('Found matching Session__c: ' + existingSession.Id);
    
                copyFields(newOpp, existingSession);
                sessionsToUpdate.add(existingSession);
            } else {
                System.debug('No matching Session__c found for Opportunity: ' + newOpp.Id);
            }
        }
    
        if (!sessionsToUpdate.isEmpty()) {
            try {
                update sessionsToUpdate;
            } catch (Exception e) {
                System.debug('Error updating sessions: ' + e.getMessage());
            }
        } else {
            System.debug('No sessions to update');
        }
    }
    

    public static void logFieldChanges(Map<Id, Opportunity> newMap, Map<Id, Opportunity> oldMap) {
        for (Id oppId : newMap.keySet()) {
            Opportunity newOpp = newMap.get(oppId);
            Opportunity oldOpp = oldMap.get(oppId);
            
            Map<String, Object> newValues = newOpp.getPopulatedFieldsAsMap();
            Map<String, Object> oldValues = oldOpp.getPopulatedFieldsAsMap();
            
            for (String fieldName : newValues.keySet()) {
                if (newValues.get(fieldName) != oldValues.get(fieldName)) {
                    // Here we log the field name and its old and new values
                    System.debug('Field changed: ' + fieldName + 
                                 ' Old Value: ' + oldValues.get(fieldName) + 
                                 ' New Value: ' + newValues.get(fieldName));
                }
            }
        }
    }
    

    public static Boolean copyFields(Opportunity opp, Session__c sess) {
        // Direct mappings from Opportunity fields to Session__c fields
        sess.Account_Name__c = opp.AccountId;
        sess.Private__c = opp.IsPrivate;
        sess.Description__c = opp.Description;
        sess.Stage__c = opp.StageName;
        sess.Amount__c = opp.Amount;
        sess.Probability__c = opp.Probability;
        sess.Expected_Revenue__c = opp.ExpectedRevenue;
        sess.Quantity__c = opp.TotalOpportunityQuantity;
        sess.CloseDate__c = opp.CloseDate;
        sess.Type__c = opp.Type;
        sess.Next_Step__c = opp.NextStep;
        sess.Lead_Source__c = opp.LeadSource;
        sess.Forecast_Category__c = opp.ForecastCategoryName;
        sess.Related_Opportunity__c = opp.Id;

        // Lists to hold debug information
        List<String> notCreatableOrUpdateable = new List<String>();
        List<String> notSelectedToBeCopied = new List<String>();
        List<String> doesNotExistOnSession = new List<String>();

        // Get the RecordType DeveloperName from the Opportunity's RecordTypeId
        String oppRecordTypeName = opp.RecordTypeId != null
            ? [SELECT DeveloperName FROM RecordType WHERE Id = :opp.RecordTypeId].DeveloperName
            : null;
    
        // Find the corresponding RecordTypeId for Session__c using the DeveloperName
        List<RecordType> sessionRecordTypes = [SELECT Id FROM RecordType WHERE SObjectType = 'Session__c' AND DeveloperName = :oppRecordTypeName LIMIT 1];
        if (sessionRecordTypes.isEmpty()) {
            return false; // Exit the method if no matching RecordType is found
        }
        Id sessionRecordTypeId = sessionRecordTypes[0].Id;
    
        // Map fields from Opportunity to Session__c
        Map<String, Schema.SObjectField> oppFieldMap = Opportunity.sObjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> sessFieldMap = Session__c.sObjectType.getDescribe().fields.getMap();
        Set<String> directMappedFields = new Set<String>{'IsPrivate', 'Description', 'StageName', 'Amount', 'Probability', 'ExpectedRevenue', 'TotalOpportunityQuantity', 'CloseDate', 'Type', 'NextStep', 'LeadSource', 'ForecastCategoryName', 'RecordTypeId'};

        for (String fieldName : oppFieldMap.keySet()) {
            if (sessFieldMap.containsKey(fieldName)) {
                if (shouldCopyField(fieldName)) {
                    Schema.DescribeFieldResult fdr = oppFieldMap.get(fieldName).getDescribe();
                    if (fdr.isCreateable() && fdr.isUpdateable()) {
                        sess.put(fieldName, opp.get(fieldName));
                    } else {
                        notCreatableOrUpdateable.add(fieldName);
                    }
                } else {
                    notSelectedToBeCopied.add(fieldName);
                }
            } else {
                doesNotExistOnSession.add(fieldName);
            }
        }

        // Debug the lists
        System.debug('Fields not creatable or updateable: ' + String.join(notCreatableOrUpdateable, ', '));
        System.debug('Fields not selected to be copied: ' + String.join(notSelectedToBeCopied, ', '));
        System.debug('Fields that do not exist on Session__c: ' + String.join(doesNotExistOnSession, ', '));
    
        // If we found a matching Session__c RecordType, set it on the new Session__c record
        if(sessionRecordTypeId != null) {
            sess.RecordTypeId = sessionRecordTypeId;
        }

        return true; // Return true if the process should continue
    }

    private static Boolean shouldCopyField(String fieldName) {
        // A list of fields to exclude from cloning
        Set<String> fieldsToExclude = new Set<String>{
            'LastModifiedDate', 'SystemModstamp', 'Name', 'Id'
        };
        // Return false if the field is in the exclude list, true otherwise
        return !fieldsToExclude.contains(fieldName);
    }
}