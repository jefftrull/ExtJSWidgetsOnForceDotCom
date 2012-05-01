/* 
Copyright 2011 Jeff Trull <jetrull@sbcpublic.net>

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
public with sharing class HierarchyController {
    // Controller for displaying and modifying record hierarchy of any object using ExtJS TreePanel view
    // by Jeff Trull <jetrull@sbcglobal.net> 2010-12-03

    // functionality for populating tree nodes
    // Corresponds directly to values expected by ExtJS NodeInterface class
    public class FetchData {
        public ID id {get; set;}
        public String text {get; set;}
        public Boolean loaded {get; set;}
        public Boolean expandable {get; set;}
        public Boolean leaf {get; set;}
    }
    public class Request {
        public String node {get; set;}
        public String sobjname {get; set;}
    }
    @RemoteAction
    public static List<FetchData> findChildObjects(Request req) {
        String fetchObject = req.sobjname;
        String fetchParentId = req.node;
        // Our goal is to determine the set of children of the supplied node, and also
        // 1) whether they themselves have children, or
        // 2) whether they are 5th level (and thus cannot have children added)
		// I can get the level of the children at the same time as I list them
        if (fetchParentId == 'root') {
            fetchParentId = '';  // workaround because an Ext TreeNode cannot have an empty ID
        }
        // dynamic SOQL so we can change object name
        String querystr = 'SELECT Id, Name, Parent.Parent.Parent.Parent.Id, ParentId FROM ' + fetchObject + ' WHERE ParentId=\'' + fetchParentId + '\'';
        Map<ID, String> Id2Name = new Map<ID, String>();        // record data as we get it back
        List<SObject> childObjects = Database.query(querystr);
        for (sObject qobj : childObjects) {
            Id2Name.put(qobj.id, (String)qobj.get('Name'));
        }
        Boolean isLvl5 = false;   // children will all be the same level (1 plus their parent's level)
        if (!childObjects.isEmpty() && 
        	childObjects[0].getSObject('Parent') != null &&
        	childObjects[0].getSObject('Parent').getSObject('Parent') != null &&
        	childObjects[0].getSObject('Parent').getSObject('Parent').getSObject('Parent') != null &&
        	childObjects[0].getSObject('Parent').getSObject('Parent').getSObject('Parent').get('ParentId') != null) {
           	isLvl5 = true;
        }
        // Do a SOQL query to find which of the records returned in step 1 have children
        Set<ID> hasChildRecords = new Set<ID>();
        if (!Id2Name.isEmpty()) {
            // look for records whose "parentId" field matches one of those ids
            set<ID> fetchedIds = Id2Name.keySet();
            querystr = 'SELECT ParentId FROM ' + fetchObject + ' WHERE ParentId IN :fetchedIds GROUP BY ParentId';
            for (AggregateResult pc : Database.query(querystr)) {
                // AggregateResult values are returned as Objects, requiring casting
                hasChildRecords.add((ID)pc.get('ParentId'));
            }
        }

        // iterate over original set of campaigns, checking each for children and producing result list
        List<FetchData> fetchResults = new List<FetchData>();
        for (ID childid : Id2Name.keySet()) {
            FetchData fd = new FetchData();
            fd.id = childid; fd.text = Id2Name.get(childid);
            if (hasChildRecords.contains(childid)) {
                fd.expandable = true;
                fd.loaded = false;
            } else {
                fd.expandable = false;
                fd.loaded = true;
            }
            fd.leaf = isLvl5;
            fetchResults.add(fd);
        }
        return fetchResults;
    }
    // Drop functionality
    @RemoteAction
    public static Boolean setParent(String fetchObject, String parentIdToSet, ID childIdToSet) {
        // get record corresponding to ChildId, set its parent, and update
        String querystr = 'SELECT Id, ParentId FROM ' + fetchObject + ' WHERE Id=\'' + childIdToSet + '\'';
        List<SObject> results = Database.query(querystr);
        if (results.size() == 1) {
        	if (parentIdToSet == '')
        		parentIdToSet = null;
            results[0].put('ParentId', parentIdToSet);
            try {
                update results[0];
            } catch (Exception e) {
                System.debug('setParent got exception');
                return false;
            }
            return true;
        } else {
            return false;
        }
    }
}