## Summary

This PR introduces an automated workflow for importing PDF documents from the DCA Vault into Teamcenter. The process reduces manual interaction by automatically locating PDF files associated with a given item code, presenting the available documents to the user, and importing the selected file as a Teamcenter dataset linked to the newly created item.

**Related Issue:** Closes #XX

---

## Changes

- Added automatic PDF discovery within the DCA Vault based on the provided item code.
- Implemented numbered file listing to allow quick selection when multiple matching PDFs are found.
- Eliminated the need for users to manually browse Vault directories.
- Added temporary file handling for Vault-managed documents before Teamcenter import.
- Improved Teamcenter item and revision creation workflow.
- Added automatic PDF dataset creation and attachment.
- Enhanced logging and error reporting during import operations.
- Improved validation of file existence and import status.
- Added support for test item creation when duplicate item IDs are detected.

---

## How to Test

1. Run the import tool.
2. Enter a valid DCA item code.
3. Enter the item name.
4. Verify that the tool automatically searches the DCA Vault.
5. Confirm that matching PDF files are listed.
6. Select one of the available documents.
7. Proceed with the import process.
8. Verify in Teamcenter that:
   - The item was created successfully.
   - The revision was created.
   - The PDF dataset was created.
   - The selected PDF is attached correctly.
   - The document can be opened from Teamcenter.

## Checklist

- [ ] Tested locally
- [ ] Tested in Teamcenter test environment
- [ ] Vault search working correctly
- [ ] PDF selection list displayed correctly
- [ ] PDF copied from Vault successfully
- [ ] Dataset created successfully
- [ ] PDF attached to item revision
- [ ] Documentation updated
- [ ] No breaking changes introduced

---

## Additional Notes

The primary goal of this enhancement is to automate the transfer of controlled PDF documentation from the DCA Vault into Teamcenter while maintaining traceability and minimizing user input. Users are no longer required to manually locate PDF files within the Vault structure, resulting in a faster and more reliable document import process.
`
