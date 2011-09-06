public with sharing class HierarchyController {
	// Controller for displaying and modifying record hierarchy of any object using ExtJS TreePanel view
	// by Jeff Trull <jetrull@sbcglobal.net> 2010-12-03

	// functionality for populating tree nodes
	public String fetchParentId {get; set;}   // String here because it may be the literal "root"
	public String fetchObject {get; set;}
	public class FetchData {
		public ID id {get; set;}
		public String name {get; set;}
		public Boolean hasChildren {get; set;}
	}
	public List<FetchData> fetchResults {get; set;}
	public void findChildObjects() {
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
		Set<ID> hasChildRecords = new Set<ID>();
		if (fetchedIds != '') {
			// that's just the records whose "parentId" field matches one of those ids
			querystr = 'select ParentId from ' + fetchObject + ' where ParentId in (' + fetchedIds + ') group by ParentId';
			for (AggregateResult pc : Database.query(querystr)) {
				// AggregateResult values are returned as Objects, requiring casting
				System.debug('adding parentid ' + pc.get('ParentId'));
				hasChildRecords.add((ID)pc.get('ParentId'));
			}
		}
		// iterate over original set of campaigns, checking each for children and producing result list
		fetchResults = new List<FetchData>();
		for (ID childid : Id2Name.keySet()) {
			FetchData fd = new FetchData();
			fd.id = childid; fd.name = Id2Name.get(childid);
			if (hasChildRecords.contains(childid)) {
				fd.hasChildren = true;
			} else {
				fd.hasChildren = false;
			}
			fetchResults.add(fd);
		}
	}
	// Drop functionality
	public String parentIdToSet {get; set;}
	public ID childIdToSet  {get; set;}
	public Boolean idSetSuccess {get; set;}
	public void setParent() {
		// get record corresponding to ChildId, set its parent, and update
		String querystr = 'select Id, ParentId from ' + fetchObject + ' where Id=\'' + childIdToSet + '\'';
		List<SObject> results = Database.query(querystr);
		idSetSuccess = false;
		if (parentIdToSet == '') {
			parentIdToSet = null;
		}
		if (results.size() == 1) {
			results[0].put('ParentId', parentIdToSet);
			try {
				update results[0];
			} catch (Exception e) {
				System.debug('setParent got exception');
				return;
			}
			System.debug('setParent returning true');
			idSetSuccess = true;
		}
	}
}