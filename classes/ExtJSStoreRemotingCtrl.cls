/*
Copyright 2011 Jeff Trull <jetrull@sbcglobal.net>

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/  
public with sharing class ExtJSStoreRemotingCtrl {
    // a class for supplying field property info to the VF component for use in setting up the grid
    public class FieldInfo {
        public String name;
        public Boolean modifiable;
        public Boolean sortable;
        public Boolean nillable;
        public String fieldType;
        public String label;
        public List<List<String> > picklistValues;      // a list of string pairs as needed by picklist column editor
    }
    
    public class DescribeException extends Exception {}

    // get object metadata and supply to component
   @RemoteAction
    public static List<FieldInfo>
    describeFields(String objName,
                   List<String> fieldNames) {
        Map<String, Schema.SObjectType> objTypeMap = Schema.getGlobalDescribe();
        if (!objTypeMap.containsKey(objName)) {
            throw new DescribeException('No SObject named ' + objName + ' found');
        }
        // TODO: check for accessibility as well
        Schema.SObjectType sobj = objTypeMap.get(objName);
        Map<String, Schema.SObjectField> fieldMap = sobj.getDescribe().fields.getMap();
        // iterate, supplying meta information in format Ext likes
        List<FieldInfo> result = new List<FieldInfo>();
        for (String field : fieldNames) {
            if (!fieldMap.containsKey(field)) {
                throw new DescribeException('No field named ' + field + ' found in SObject ' + objName);
            }
            Schema.DescribeFieldResult dfr = fieldMap.get(field).getDescribe();
            FieldInfo fi = new FieldInfo();
            fi.name = field;
            fi.modifiable = dfr.isCreateable() | dfr.isUpdateable();
            fi.sortable = dfr.isSortable();
            fi.nillable = dfr.isNillable();
            fi.fieldType = String.valueOf(dfr.getType()).toLowerCase();
            fi.label = dfr.getLabel();
            if (dfr.getType() == Schema.DisplayType.Picklist) {
                fi.picklistValues = new List<List<String> >();
                for (Schema.PicklistEntry plv : dfr.getPicklistValues()) {
                    if (plv.isActive()) {
                        fi.picklistValues.add(new String[]{plv.getLabel(), plv.getValue()});
                    }
                }
                // add empty string option if nillable
                if (dfr.isNillable()) {
                    fi.picklistValues.add(new String[]{'', null});
                }
            }
            result.add(fi);
        }
        return result;
    }

    // a user-defined class that will serialize to the JSON expected by the ExtJS DirectProxy api methods
    public class CRUDResponse {
        public Boolean success;
        public String errorMessage;
        public List<SObject> records;
        public Integer total;
        CRUDResponse() {
            records = new List<SObject>();
            success = true;
        }
    }
    
    // Unfortunately JS Remoting member functions must be static, so cannot access non-static class members,
    // which means we cannot cache query results in this controller but must respond to each request anew

    public class QueryObj {
        public String sobjname;
        public String fields;
        public Integer start;
        public Integer recordCount;
        public List<Map<String, String> > sortParams;
    }

    // turn grid's page load/sort request into SOQL and return data
    @RemoteAction
    public static CRUDResponse query(QueryObj qobj) {
        CRUDResponse resp = new CRUDResponse();

        // construct a count query.  Two SOQL statements - one COUNT(), one with LIMIT -
        // seems to be faster than one query without LIMIT
        String countstr = 'SELECT COUNT() FROM ' + qobj.sobjname;
        countstr = String.escapeSingleQuotes(countstr);
        resp.total = Database.countQuery(countstr);   // ExtJS grid needs the true total here

        // construct a query string
        String qstr = 'SELECT ' + qobj.fields + ' FROM ' + qobj.sobjname;
        if (qobj.sortParams != null) {
            qstr += ' ORDER BY ';
            // collect sort fields/directions
            qstr += qobj.sortParams[0].get('property');
            for (Integer i = 1; i < qobj.sortParams.size(); i++) {
                qstr += ',' + qobj.sortParams[i].get('property');
            }
            // SOQL only supports a single direction, so ignoring others. Probably should return error instead.
            qstr += ' ' + qobj.sortParams[0].get('direction');
        }
        // data reduction: LIMIT and OFFSET
        // calculate the index of the first record returned by the query
        // OFFSET has some tricky limitations.  First, the maximum value is 2000, so if the first desired record
        // is beyond that point we will have to access some records we don't want.  Second, the use of OFFSET
        // causes the maximum number of records returned to be 200 - this appears to be undocumented.
		Integer startrec = 0;
        if (qobj.recordCount > 200) {
        	// cannot use OFFSET; start at zero and include records before our desired region
        	Integer reclimit = qobj.start + qobj.recordCount;
        	qstr += ' LIMIT ' + String.valueOf(reclimit);
        } else {
        	startrec = Math.min(qobj.start, 2000);
        	// record count to get is the sum of the mandatory unwanted records (those over 2000) and those we want
        	Integer reclimit = (qobj.start - startrec) + qobj.recordCount;
        	qstr += ' LIMIT ' + String.valueOf(reclimit);
	        qstr += ' OFFSET ' + String.valueOf(startrec);
		}
        qstr = String.escapeSingleQuotes(qstr);   // sanitize for SOQL injection
        Integer current_result = startrec;        // initialize with the true offset
        String[] fieldNames = qobj.fields.split(',');
        try {
            for (List<SObject> rlit : Database.query(qstr)) {
                for (SObject rit : rlit) {
                    if ((current_result >= qobj.start) && (current_result < (qobj.start + qobj.recordCount))) {
                        resp.records.add(rit);
                    }
                    current_result++;
                }
            }
        } catch (Exception e) {
            resp.success = false;
            resp.records = null;
            resp.errorMessage = e.getMessage();
            return resp;
        }
        return resp;
    }

    // C,U,D methods from DirectProxy all have the same argument format:
    public class CRUDData {
        public String sobjname;
        public String fields;
        public List<Map<String, String> > records;
    }

    // Utility method to refresh newly created/updated objects after the DML operation, for returning to the grid
    public static CRUDResponse refreshObjects(CRUDData crudData, List<SObject> sobjs) {
        CRUDResponse resp = new CRUDResponse();

        String objName = crudData.sobjname;
        String fieldList = crudData.fields;
        String[] fieldNames = fieldList.split(',');
        Set<ID> updatedIds = new Set<ID>();
        for (SObject sobj : sobjs) {
            updatedIds.add(sobj.id);
        }
        for (List<SObject> rlit : Database.query('SELECT ' + fieldList + ' FROM ' + objName +
                                                 ' WHERE Id IN :updatedIds')) {
            for (SObject rit : rlit) {
                resp.records.add(rit);
            }
        }
        return resp;        
    }

    // Create and Update are very similar.
    // Create supplies all specified fields but no Id; Update specifies Id and only the fields that changed
    @RemoteAction
    public static CRUDResponse create(CRUDData crudData) {
        CRUDResponse resp = new CRUDResponse();
        List<SObject> sobjs = unpackSobjects('create', crudData, resp);
        if (!resp.success) {
            return resp;
        }

        try {
            insert sobjs;
        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = 'create: insert failed with error ' + e.getMessage();
            return resp;
        }

        return refreshObjects(crudData, sobjs);
    }

    // "update" and "delete" are keywords so must pick something else
    // Ken Thompson is supposed to have said that if he could redo anything about Unix,
    // he'd spell "creat" with an extra "e".  So in that spirit:
    @RemoteAction
    public static CRUDResponse updat(CRUDData crudData) {
        CRUDResponse resp = new CRUDResponse();
        List<SObject> sobjs = unpackSobjects('update', crudData, resp);
        if (!resp.success) {
            return resp;
        }

        try {
            update sobjs;
        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = 'update: failed with error ' + e.getMessage();
            return resp;
        }

        return refreshObjects(crudData, sobjs);
    }
    
    @RemoteAction
    public static CRUDResponse delet(CRUDData crudData) {
        CRUDResponse resp = new CRUDResponse();

        // produce a list of IDs from each supplied sObject
        List<Map<String, String> > sobjs = crudData.records;
        List<String> idlist = new List<String>();
        for (Map<String, String> sobj : sobjs) {
            idlist.add(sobj.get('Id'));
        }
        
        try {
            Database.delete(idlist);
        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = 'delete: failed with error ' + e.getMessage();
        }
        
        return resp;
    }

    // utility functions
    
    // create, update, and delete all supply things that resemble SObjects
    // (although update only has changed fields and delete only has IDs)

	// this method may seem a bit redundant when Remoting can now accept SObjects.  There are two important
	// things we do here that can't be done just by accepting List<sObject> in our methods:
	// 1) a generic sObject (not created from a describe "token") and without an Id cannot be used in DML,
	//    so we have to generate a new sObject anyway for "create" operations
	// 2) There is something funny about Date fields - I haven't been able to find a format
	//    that the server will accept.  A plain Date parameter can be supplied via UTC string, but
	//    one that is a field inside an SObject gives problems.  Converting from a string works fine though.
    static List<SObject> unpackSobjects(String action, CRUDData crudData, CRUDResponse resp) {
        resp.success = false;

        // use "base" params to find the sobject type we need to create
        if (crudData.sobjname == null) {
            resp.errorMessage = 'SObject name not supplied in client call';
            return null;
        }
        String objName = crudData.sobjname;
        Map<String, Schema.SObjectType> objTypeMap = Schema.getGlobalDescribe();
        if (!objTypeMap.containsKey(objName)) {
            resp.errorMessage = 'No SObject named ' + objName + ' found';
            return null;
        }
        Schema.SObjectType sobjToken = objTypeMap.get(objName);  // "token" representing this sObject type
        Map<String, Schema.SObjectField> fieldMap = sobjToken.getDescribe().fields.getMap();
        
        if (crudData.records == null) {
            resp.errorMessage = 'argument ' + crudData + ' contained no records field';
            return null;
        }
        List<Map<String, String> > records = crudData.records;
        List<SObject> sobjs = new List<SObject>();
        for (Map<String, String> recmap : records) {
            SObject sobj;
            if (recmap.containsKey('Id')) {
                // create SObject using supplied Id (setting it as a field will fail)
                sobj = sobjToken.newSObject(recmap.get('Id'));
            } else {
                sobj = sobjToken.newSObject();
            }
            for (String k : recmap.keySet()) {
                // definitely an empty value if null, empty string, or the string 'null' but the type is not string
                // TODO it does seem like I should be able to map 'null' to null somehow in mapUnpack()
                Boolean emptyValue = (recmap.get(k) == null) || (recmap.get(k) == '') ||
                                      (fieldMap.get(k).getDescribe().getType() != Schema.DisplayType.string) &&
                                      (recmap.get(k) == 'null');
                if ((k != 'Id') &&  // never try to set Id this way (see above)
                    ((action == 'update') || // don't try to set an empty value unless this is an update
                     !emptyValue)) {
                    if (emptyValue) {
                        sobj.put(k, null);
                    } else if (fieldMap.get(k).getDescribe().getType() == Schema.DisplayType.date) {
                        // Date fields appear to need to be set from Date values, not strings, so:
                        sobj.put(k, Date.valueOf(recmap.get(k)));
                    } else if (fieldMap.get(k).getDescribe().getType() == Schema.DisplayType.boolean) {
                        sobj.put(k, Boolean.valueOf(recmap.get(k)));
                    } else if (fieldMap.get(k).getDescribe().getType() == Schema.DisplayType.integer) {
                        sobj.put(k, Integer.valueOf(recmap.get(k)));
                    } else if (fieldMap.get(k).getDescribe().getType() == Schema.DisplayType.double) {
                        sobj.put(k, Double.valueOf(recmap.get(k)));
                    } else {
                        sobj.put(k, recmap.get(k));
                    } // TODO: handle other types, esp. Currency
                }
            }
            sobjs.add(sobj);
        }
        resp.success = true;
        return sobjs;
    }
}