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
public class CampaignHierarchyController {
    class CampaignHierarchyLevel {
        // representing a level in the tree - an ID and a list of child nodes
        Campaign camp;
        List<CampaignHierarchyLevel> children;
        CampaignHierarchyLevel(Campaign c) {
            camp = c;
            children = new List<CampaignHierarchyLevel>();
        }
    }
    // for communicating with VF we have a sort of vestigial Campaign class
    public class CampaignLevelInfo {
        // four fields from Campaign, plus a flag to tell us if it's a leaf
        public ID parentId {get;set;}
        public ID id {get;set;}
        public String name {get;set;}
        public Boolean isLeaf {get;set;}
        public Boolean isActive {get;set;}
    }
        
    List<CampaignHierarchyLevel> toplevel_campaigns;       // the top of our data structure
	public List<CampaignLevelInfo> CampaignTree {get;set;} // the campaign tree, flattened with parents first
    public CampaignHierarchyController() {
        // create a tree structure from the Campaign hierarchy and store it for VF reference
        toplevel_campaigns = new List<CampaignHierarchyLevel>();
        // if we fill the campaign tree by repeated SOQL queries (based on ParentId) we exceed the limit very quickly
        // instead let's do a single query for active campaigns, and process the results
        // question: would it be better to get all campaigns, and disable selecting the ones that are inactive?
        // this way we may end up missing active campaigns that are descendants of inactive ones
        Map<ID, List<Campaign>> child_campaigns = new Map<ID, List<Campaign>>();
        // for (Campaign c : [select Id, Name, ParentId from Campaign where IsActive=true]) {
        // 2011-06-28 fyc: encountered VisualForce error when we went over 1,000 campaigns, hence LIMIT 1000
        // for (Campaign c : [select Id, Name, ParentId, IsActive from Campaign order by Name DESC LIMIT 1000]) {
        // 2011-06-29 jet: alternate approach.  Filter out inactive childless campaigns (the majority)
        List<AggregateResult> parents = [SELECT ParentId FROM Campaign WHERE ParentId <> null GROUP BY ParentId];
        // turn the AggregateResult into a simple list of IDs we can use in a query
        List<ID> campaigns_with_children = new List<ID>();
        for (AggregateResult par : parents) {
        	campaigns_with_children.add((ID)par.get('ParentId'));
        }
        for (Campaign c : [SELECT Id, Name, ParentId, IsActive FROM Campaign
                                           WHERE IsActive=true OR Id IN :campaigns_with_children
                                           ORDER BY Name DESC]) {
            if (c.ParentId == null) {
                toplevel_campaigns.add(new CampaignHierarchyLevel(c));
            }
            else {
                // add this campaign to its parent's list of child campaigns
                if (!child_campaigns.containsKey(c.ParentId)) {
                    child_campaigns.put(c.ParentId, new List<Campaign>());
                }
                child_campaigns.get(c.ParentId).add(c);
            }
        }
        // now all of our campaigns are in one of two places:
        // 1) in toplevel_campaigns, if they had no parent, or
        // 2) listed as children of the appropriate parent (flat, by parent) in child_campaigns
        // now we turn this into a tree in a depth-first manner
        List<CampaignHierarchyLevel> camp_expand_stack = new List<CampaignHierarchyLevel>(toplevel_campaigns);
        CampaignTree = new List<CampaignLevelInfo>();
        while (!camp_expand_stack.isEmpty()) {
            // remove the last one from the end
            CampaignHierarchyLevel chl = camp_expand_stack.remove(camp_expand_stack.size() - 1);
            CampaignLevelInfo cli = new CampaignLevelInfo();
            cli.id = chl.camp.id;  cli.parentId = chl.camp.parentId;
            cli.name = chl.camp.name; cli.isActive = chl.camp.isActive;
            if (child_campaigns.containsKey(chl.camp.Id)) {
                // this campaign has children.  Create hierarchy levels for them and push on stack
                for (Campaign cc : child_campaigns.get(chl.camp.Id)) {
                    camp_expand_stack.add(new CampaignHierarchyLevel(cc));
                }
                cli.isLeaf = false;
            } else {
            	cli.isLeaf = true;
            }
            CampaignTree.add(cli);
        }
        SelectedCampaign = new Campaign();
    }

    public PageReference selectCampaign() {
        // do lookup and set SelectedCampaign based on ID chosen by user
        if (SelectedId != null) {
            SelectedCampaign = [select Id, Name, ParentId from Campaign where Id=:SelectedId limit 1];
        }
        return null;
    }
    public string SelectedId {get;set;}           // input from tree display
    public Campaign SelectedCampaign {get;set;}   // output result of query
    
    // Tests
    private testMethod static void testCampaignMenu() {
    	// first, make an "interesting" campaign hierarchy
    	Campaign root = new Campaign(Name = 'Apex Test Campaign Root', IsActive = true);
    	Campaign inactiveRoot = new Campaign(Name = 'Apex Test Campaign Inactive Root', IsActive = false);
    	insert root; insert inactiveRoot;

    	Campaign activeWithChildren = new Campaign(Name = 'Apex Test Campaign Active With Children', IsActive = true,
    											   ParentId = root.Id);
    	Campaign activeNoChildren = new Campaign(Name = 'Apex Test Campaign Active No Children', IsActive = true,
    											   ParentId = root.Id);
    	Campaign inactiveNonRoot = new Campaign(Name = 'Apex Test Campaign Inactive Non Root', IsActive = false,
    											   ParentId = root.Id);
    	Campaign inactiveNonRootNoChildren = new Campaign(Name = 'Apex Test Campaign Inactive Non Root No Children',
    											   IsActive = false, ParentId = root.Id);
    	insert activeWithChildren; insert activeNoChildren; insert inactiveNonRoot; insert inactiveNonRootNoChildren;

		// give (some) inactive campaigns an active child so they show up
		Campaign activeChildofInactive = new Campaign(Name = 'Apex Test Campaign Child of Inactive Root Parent', 
													  IsActive = true, ParentId = inactiveRoot.Id);
		Campaign activeChildOfInactiveNonRoot = new Campaign(Name = 'Apex Test Campaign Child of Inactive Non Root',
															 IsActive = true, ParentId = inactiveNonRoot.Id);
		// need at least one normal active campaign
		Campaign activeChildOfActive = new Campaign(Name = 'Apex Test Campaign Active Child of Active',
													ParentId = activeWithChildren.Id, IsActive = true);
		insert activeChildOfInactive; insert activeChildOfInactiveNonRoot; insert activeChildOfActive;

		CampaignHierarchyController ctrl = new CampaignHierarchyController();
		List<CampaignLevelInfo> results = ctrl.CampaignTree;

		// verify that the campaign tree looks right.
		// Our test campaigns will be mixed in with the campaigns already in the org.
		// In order to test safely, remember which campaigns we just inserted
		Set<ID> testCampaigns = new Set<ID>();
		testCampaigns.add(root.Id); testCampaigns.add(inactiveRoot.Id);
		testCampaigns.add(activeWithChildren.Id); testCampaigns.add(activeNoChildren.Id);
		testCampaigns.add(inactiveNonRoot.Id); testCampaigns.add(inactiveNonRootNoChildren.Id);
		testCampaigns.add(activeChildOfInactive.Id); testCampaigns.add(activeChildOfInactiveNonRoot.Id);
		testCampaigns.add(activeChildOfActive.Id);

		// Now let's check the hierarchy produced by our controller
		Set<ID> foundTestCampaigns = new Set<ID>();
		for (CampaignLevelInfo cli : results) {
			if (testCampaigns.contains(cli.id)) {
				// one of ours; check it
				System.assertNotEquals(cli.id, inactiveNonRootNoChildren.id);  // should never appear
				if (cli.id == root.id) {
					System.assertEquals(cli.ParentId, null);
					System.assertEquals(cli.name, root.Name);
					System.assertEquals(cli.isLeaf, false);
					System.assertEquals(cli.isActive, true);
				} else if (cli.id == inactiveRoot.id) {
					System.assertEquals(cli.ParentId, null);
					System.assertEquals(cli.name, inactiveRoot.Name);
					System.assertEquals(cli.isLeaf, false);
					System.assertEquals(cli.isActive, false);					
				} else if (cli.id == activeWithChildren.id) {
					System.assertEquals(cli.ParentId, root.Id);
					System.assertEquals(cli.name, activeWithChildren.Name);
					System.assertEquals(cli.isLeaf, false);
					System.assertEquals(cli.isActive, true);
				} else if (cli.id == activeNoChildren.id) {
					System.assertEquals(cli.ParentId, root.Id);
					System.assertEquals(cli.name, activeNoChildren.Name);
					System.assertEquals(cli.isLeaf, true);
					System.assertEquals(cli.isActive, true);
				} else if (cli.id == inactiveNonRoot.id) {
					System.assertEquals(cli.ParentId, root.Id);
					System.assertEquals(cli.name, inactiveNonRoot.Name);
					System.assertEquals(cli.isLeaf, false);
					System.assertEquals(cli.isActive, false);
				} else if (cli.id == activeChildOfInactive.id) {
					System.assertEquals(cli.ParentId, inactiveRoot.Id);
					System.assertEquals(cli.name, activeChildOfInactive.Name);
					System.assertEquals(cli.isLeaf, true);
					System.assertEquals(cli.isActive, true);
				} else if (cli.id == activeChildOfInactiveNonRoot.id) {
					System.assertEquals(cli.ParentId, inactiveNonRoot.Id);
					System.assertEquals(cli.name, activeChildOfInactiveNonRoot.Name);
					System.assertEquals(cli.isLeaf, true);
					System.assertEquals(cli.isActive, true);
				} else {
					// better be "active child of active parent"...
					System.assertEquals(cli.ParentId, activeWithChildren.id);
					System.assertEquals(cli.name, activeChildOfActive.Name);
					System.assertEquals(cli.isLeaf, true);
					System.assertEquals(cli.isActive, true);
				}
				// remember that we saw this one
				foundTestCampaigns.add(cli.id);
			}
		}
		System.assertEquals(foundTestCampaigns.size(), 8);  // all except inactive with no children should appear
		
		// Finally, test the selection mechanism with an active campaigns
		ctrl.selectedId = String.valueOf(activeChildOfActive.id);
		System.assertEquals(ctrl.selectCampaign(), null);  // no redirect ever
		System.assertEquals(ctrl.SelectedCampaign.id, activeChildOfActive.id);
    }
}