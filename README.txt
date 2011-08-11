A collection of examples for using ExtJS widgets with Salesforce.com data as a back end.

To use these, you need to create and upload an ExtJS "resource", which is just a zip file containing the
ExtJS distribution.  You can remove any unneeded parts (samples, documentation) before uploading to your org.
Name the resource ExtJS and update the version numbers in the components as needed to reflect the version of
Ext you are actually using.

The resource I originally tested with consists of the Ext 3.4.0 release, as downloaded from:

http://www.sencha.com/products/extjs3/download/ext-js-3.4

with the "docs" directory removed, and everything under "examples" removed except for:

ext-3.4.0/examples/shared/icons/fam/add.gif  
ext-3.4.0/examples/shared/icons/fam/delete.gif  
ext-3.4.0/examples/shared/icons/save.gif  

which are needed for the grids.  The resulting file is a little over 4MB.  It may be possible to reduce the size
further, but I haven't investigated yet.

For the 4.0.2a release I removed every subdirectory except "resources" and one subdirectory under examples,
"examples/shared/icons".  I think there are useful icons other than just the above three, so it's worth
preserving them for other code.
