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
        // because we have to determine if each child object has children, we must do two separate queries:
        // one to get the children of the supplied object ID, the other to count the children of the children
        if (fetchParentId == 'root') {
            fetchParentId = '';  // workaround because an Ext TreeNode cannot have an empty ID
        }
        // dynamic SOQL so we can change object name
        String querystr = 'select Id, Name from ' + fetchObject + ' where ParentId=\'' + fetchParentId + '\'';
        Map<ID, String> Id2Name = new Map<ID, String>();        // record data as we get it back
        String fetchedIds = '';
        for (sObject qobj : Database.query(querystr)) {
            Id2Name.put(qobj.id, (String)qobj.get('Name'));
            String qid = '\'' + qobj.id + '\'';
            if (fetchedIds == '') {
                fetchedIds = qid;
            } else {
                fetchedIds += (',' + qid);
            }
        }
        // Do a SOQL query to find which of the records returned in step 1 have children
        // and which are lvl5 (and thus mandatory leaf)
        Set<ID> hasChildRecords = new Set<ID>();
        Set<ID> isLvl5 = new Set<ID>();
        if (fetchedIds != '') {
            // look for records whose "parentId" field matches one of those ids
            querystr = 'SELECT ParentId FROM ' + fetchObject + ' WHERE ParentId IN (' + fetchedIds + ') GROUP BY ParentId';
            for (AggregateResult pc : Database.query(querystr)) {
                // AggregateResult values are returned as Objects, requiring casting
                hasChildRecords.add((ID)pc.get('ParentId'));
            }
            querystr = 'SELECT Id, Parent.Parent.Parent.Parent.Id FROM ' + fetchObject + 
                           ' WHERE Id IN (' + fetchedIds + ') AND Parent.Parent.Parent.Parent.Id != null';
			for (SObject obj : Database.query(querystr)) {
				isLvl5.add((ID)obj.get('Id'));
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
            fd.leaf = isLvl5.contains(childid);
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
            System.debug('setParent returning true');
            return true;
        } else {
            return false;
        }
    }
}