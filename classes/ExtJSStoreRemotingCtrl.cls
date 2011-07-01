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
global with sharing class ExtJSStoreRemotingCtrl {
	// a class for supplying field property info to the VF component for use in setting up the grid
    global class FieldInfo {
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
    global static List<FieldInfo>
    describeFields(String objName,
                   String fieldList) {
        String[] fieldNames = fieldList.split(',');
        Map<String, Schema.SObjectType> objTypeMap = Schema.getGlobalDescribe();
        if (!objTypeMap.containsKey(objName)) {
        	throw new DescribeException('No SObject named ' + objName + ' found');
        }
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
    global class CRUDResponse {
        public Boolean success;
        public String errorMessage;
        public List<Map<String, String> > records;
        public Integer total;
        CRUDResponse() {
            records = new List<Map<String, String> >();
        }
    }
    
    // Unfortunately JS Remoting member functions must be static, so cannot access non-static class members,
    // which means we cannot cache query results in this controller but must respond to each request anew

	// turn grid's page load/sort request into SOQL and return data
	@RemoteAction
	global static CRUDResponse query(String arg1) {
		Map<String, String> params = mapUnpack(arg1);
		String objName = params.get('sobjname');
        String fieldList = params.get('fields');
        Integer startRecord = Integer.valueOf(params.get('start'));
        Integer recordCount = Integer.valueOf(params.get('limit'));
        String sortField, sortDir;
        if (params.get('sort') != null) {
        	sortField = params.get('sort');
        	sortDir = params.get('dir');
        }
        // construct a query string
        String qstr = 'SELECT ' + fieldList + ' FROM ' + objName;
		if (sortField != null) {
			qstr += ' ORDER BY ' + sortField + ' ' + sortDir;
		}
		qstr = String.escapeSingleQuotes(qstr);   // sanitize for SOQL injection
        // no LIMIT here or our "total" numbers will be wrong for the grid
        // alternatively: do two SOQL calls, one to get the total, one to get requested data
        CRUDResponse resp = new CRUDResponse();
        Integer current_result = 0;
        String[] fieldNames = fieldList.split(',');
        try {
	        for (List<SObject> rlit : Database.query(qstr)) {
	            for (SObject rit : rlit) {
	                if ((current_result >= startRecord) && (current_result < (startRecord + recordCount))) {
	                	Map<String, String> objmap = new Map<String, String>();
	                	for (String field : fieldNames) {
	                		if (rit.get(field) != null) {
	                			objmap.put(field, String.valueOf(rit.get(field)));
	                		}
	                	}
	                    resp.records.add(objmap);
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
        resp.success = true;
		resp.total = current_result;
        return resp;
	}

	// Create and Update are very similar.
	// Create supplies all specified fields but no Id; Update specifies Id and only the fields that changed
    @RemoteAction
    global static CRUDResponse create(String crudData) {
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

    	for (SObject sobj : sobjs) {
    		Map<String, String> rec = new Map<String, String>();
    	    rec.put('id', String.valueOf(sobj.Id));
    		resp.records.add(rec);
    	}
    	return resp;
    }

    // "update" and "delete" are keywords so must pick something else
    // Ken Thompson is supposed to have said that if he could redo anything about Unix, he'd spell "creat" with an extra "e"
	// So in that spirit:
    @RemoteAction
    global static CRUDResponse updat(String crudData) {
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

    	for (SObject sobj : sobjs) {
    		Map<String, String> rec = new Map<String, String>();
    	    rec.put('id', String.valueOf(sobj.Id));
    		resp.records.add(rec);
    	}
    	return resp;
    }
    
    @RemoteAction
    global static CRUDResponse delet(String crudData) {
    	Map<String, String> argobj = mapUnpack(crudData);
		// Ext supplies just a list of Id's to delete.  Let's take advantage of that and not construct SObjects
    	List<String> idlist = listUnpack(argobj.get('records'));
    	CRUDResponse resp = new CRUDResponse();
    	resp.success = true;
    	
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
	static List<SObject> unpackSobjects(String action, String crudData, CRUDResponse resp) {
		Map<String, String> argobj = mapUnpack(crudData);
		resp.success = false;

		// use "base" params to find the sobject type we need to create
		if (!argobj.containsKey('sobjname')) {
			resp.errorMessage = 'SObject name not supplied in client call';
			return null;
		}
		String objName = argobj.get('sobjname');
        Map<String, Schema.SObjectType> objTypeMap = Schema.getGlobalDescribe();
        if (!objTypeMap.containsKey(objName)) {
        	resp.errorMessage = 'No SObject named ' + objName + ' found';
        	return null;
        }
        Schema.SObjectType sobjToken = objTypeMap.get(objName);  // "token" representing this sObject type
        Map<String, Schema.SObjectField> fieldMap = sobjToken.getDescribe().fields.getMap();
        
    	if (!argobj.containsKey('records')) {
    		resp.errorMessage = 'argument ' + crudData + ' contained no records field';
    		return null;
    	}
    	List<String> records = listUnpack(argobj.get('records'));
    	List<SObject> sobjs = new List<SObject>();
    	for (String rec : records) {
    		Map<String, String> recmap = mapUnpack(rec);
    		SObject sobj;
    		if (recmap.containsKey('id')) {
    			// create SObject using supplied Id (setting it as a field will fail)
    			sobj = sobjToken.newSObject(recmap.get('id'));
    		} else {
    			sobj = sobjToken.newSObject();
    		}
			for (String k : recmap.keySet()) {
				if ((k != 'id') &&  // never try to set Id this way (see above)
					((action == 'update') || // don't try to set an empty value unless this is an update
					 (recmap.get(k) != null) && (recmap.get(k) != ''))) {
					// Date fields appear to need to be set from Date values, not strings, so:
					if (fieldMap.get(k).getDescribe().getType() == Schema.DisplayType.date) {
						if ((recmap.get(k) == null) || (recmap.get(k) == '')) {
							// don't try to parse as a date - just use null
							sobj.put(k, null);
						} else {
							sobj.put(k, Date.valueOf(recmap.get(k)));
						}
					} else {
						sobj.put(k, recmap.get(k));
					}
				}
			}
			sobjs.add(sobj);
    	}
    	resp.success = true;
    	return sobjs;
	}

	// Extremely remedial JSON "parser".  For a proper implementation see Ron Hess's popular contribution on Code Share

	// Unpack client parameters. No error checking.
	static Map<String, String> mapUnpack(String pmap) {
		Map<String, String> result = new Map<String, String>();
		pmap = pmap.trim();									// remove leading/trailing spaces
		pmap = pmap.substring(1, pmap.lastIndexOf('}'));	// remove leading/trailing curly braces

		// pick up "key=value" pairs.  Treat square brackets as quotes
		Integer offset = 0;   // current scanning point
		while (pmap.indexOf('=', offset) > 0) {
			// key=value pairs remain
			Integer eqOffset = pmap.indexOf('=', offset);
			String key = pmap.substring(offset, eqOffset);
			// find the end of the value
			Integer valueEnd;   // one past the end, actually (see "substring" documentation)
			if (((eqOffset + 1) < pmap.length()) && // '=' may be immediately followed by end of string for empty values
				(pmap.substring(eqOffset + 1, eqOffset + 2) == '[')) {
				// skip to end of square brackets (note only one level supported)
				valueEnd = pmap.indexOf(']', eqOffset + 1) + 1;
			} else if (pmap.indexOf(', ', eqOffset + 1) > 0) {
				// we are in the middle of a list
				valueEnd = pmap.indexOf(', ', eqOffset + 1);
			} else {
				// use the end of the string
				valueEnd = pmap.length();
			}
			result.put(key, pmap.substring(eqOffset + 1, valueEnd));

			// move to next key/value pair
			offset = valueEnd;
			// skip separators, if any
			if ((offset < (pmap.length() - 1)) && (pmap.substring(offset, offset + 2) == ', ')) {
				offset += 2;
			}
		}
		return result;
	}

	static List<String> listUnpack(String plist) {
		// unpack square bracketed list, treating curly braces as quotes
		List<String> result = new List<String>();
		plist = plist.trim();
		plist = plist.substring(1, plist.lastIndexOf(']'));

		List<String> items = new List<String>();
		Integer offset = 0;   // current scanning point
		while (offset < plist.length()) {
			Integer valueEnd;
			if (plist.substring(offset, offset + 1) == '{') {
				valueEnd = plist.indexOf('}', offset + 1) + 1;
			} else if (plist.indexOf(', ', offset) > 0) {
				valueEnd = plist.indexOf(', ', offset);
			} else {
				// use the end of the string
				valueEnd = plist.length();
			}
			items.add(plist.substring(offset, valueEnd));
			offset = valueEnd;
			if ((offset < (plist.length() - 1)) && (plist.substring(offset, offset + 2) == ', ')) {
				offset += 2;
			}
		}
		return items;
	}
}