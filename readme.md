### Create a tag locally:
````bash
git tag v1.0.1
```

### Push that specific tag to GitHub:
```bash
git push origin v1.0.1
```

### Google sheet data sync with Supabase database
```javascript
// Add any tab names here that you DO NOT want to sync to Supabase
// Added 'StudentDetails' because it does not have an 'id' column.
const EXCLUDED_TABS = ['Dashboard', 'Instructions'];

/**
 * Creates a custom menu in Google Sheets when the document opens.
 */
function onOpen() {
  const ui = SpreadsheetApp.getUi();
  
  ui.createMenu('Supabase Sync')
    .addItem('Sync All Tabs Now', 'syncAllTabsToSupabase')
    .addToUi();
}

/**
 * MAIN FUNCTION: Run this to sync all tabs.
 */
function syncAllTabsToSupabase() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  
  // Show a notification that the sync has started
  ss.toast('Starting sync to Supabase. This may take a moment...', 'Sync Started', 5);

  const sheets = ss.getSheets();

  for (const sheet of sheets) {
    const tableName = sheet.getName();
    
    if (EXCLUDED_TABS.includes(tableName)) {
      Logger.log(`Skipping excluded tab: ${tableName}`);
      continue;
    }

    Logger.log(`=== Starting sync for tab: ${tableName} ===`);
    try {
      syncSheetData(sheet, tableName);
    } catch (error) {
      Logger.log(`ERROR on tab ${tableName}: ${error.message}`);
    }
  }
  
  Logger.log("=== ALL TABS SYNC COMPLETED ===");
  
  // Show a notification that the sync is finished
  ss.toast('All tabs have been successfully synced to Supabase!', 'Sync Complete', 5);
}

function getSupabaseCredentials() {
  const scriptProps = PropertiesService.getScriptProperties();
  const SUPABASE_URL = scriptProps.getProperty('SUPABASE_URL'); 
  const SUPABASE_KEY = scriptProps.getProperty('SUPABASE_SERVICE_ROLE_KEY'); 

  if (!SUPABASE_URL || !SUPABASE_KEY) {
    throw new Error("Supabase URL or Key is missing from Script Properties.");
  }
  return { SUPABASE_URL, SUPABASE_KEY };
}

function fetchSupabaseIds(tableName) {
  const { SUPABASE_URL, SUPABASE_KEY } = getSupabaseCredentials();
  
  // encodeURIComponent handles spaces in tab names (e.g., "Monthly Calendar" -> "Monthly%20Calendar")
  const safeTableName = encodeURIComponent(tableName);
  const url = `${SUPABASE_URL}/rest/v1/${safeTableName}?select=id`;
  
  const options = {
    method: 'GET',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json'
    },
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(url, options);
  
  if (response.getResponseCode() >= 200 && response.getResponseCode() < 300) {
    const data = JSON.parse(response.getContentText());
    return new Set(data.map(record => String(record.id)));
  } else {
    // If the table doesn't exist in Supabase, PostgREST usually returns 404 or 400.
    throw new Error(`Failed to fetch IDs. Does the table exist in Supabase? Response: ${response.getContentText()}`);
  }
}

/**
 * Processes a single sheet/table.
 */
function syncSheetData(sheet, tableName) {
  const values = sheet.getDataRange().getValues();
  if (values.length < 2) {
    Logger.log(`No data to sync in ${tableName}.`);
    return;
  }

  const headers = values[0].map(h => String(h || '').trim());
  
  // Safety check: ensure there is an 'id' column
  if (!headers.includes('id')) {
    Logger.log(`Skipping ${tableName}: No 'id' column found in header row.`);
    return;
  }

  const allRows = values.slice(1).map(r => rowArrayToObject(headers, r));
  const existingSupabaseIds = fetchSupabaseIds(tableName);
  
  const needModification = [];
  const needInsertion = [];

  allRows.forEach(row => {
    const rowId = String(row.id).trim();
    
    // Check if row is completely empty (Google Sheets sometimes returns empty rows at the bottom)
    const hasData = Object.keys(row).some(key => key !== 'id' && row[key] !== '');
    if (!hasData && !rowId) return; 

    if (rowId && existingSupabaseIds.has(rowId)) {
      needModification.push(row);
    } else {
      // If the ID is empty, delete the property so Supabase auto-generates it (if applicable)
      if (!rowId) {
        delete row.id;
      }
      needInsertion.push(row);
    }
  });

  // Execute Updates
  if (needModification.length > 0) {
    Logger.log(`Updating ${needModification.length} records in ${tableName}...`);
    updateSupabaseRecords(needModification, tableName);
  }

  // Execute Inserts
  if (needInsertion.length > 0) {
    Logger.log(`Inserting ${needInsertion.length} records into ${tableName}...`);
    insertSupabaseRecords(needInsertion, tableName);
  }
  
  if (needModification.length === 0 && needInsertion.length === 0) {
     Logger.log(`No new inserts or updates needed for ${tableName}.`);
  }
}

function insertSupabaseRecords(records, tableName) {
  const { SUPABASE_URL, SUPABASE_KEY } = getSupabaseCredentials();
  const safeTableName = encodeURIComponent(tableName);
  const url = `${SUPABASE_URL}/rest/v1/${safeTableName}`;
  
  const options = {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json'
    },
    payload: JSON.stringify(records),
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(url, options);
  checkResponse(response, "Insert", tableName);
}

function updateSupabaseRecords(records, tableName) {
  const { SUPABASE_URL, SUPABASE_KEY } = getSupabaseCredentials();
  const safeTableName = encodeURIComponent(tableName);
  const url = `${SUPABASE_URL}/rest/v1/${safeTableName}?on_conflict=id`;
  
  const options = {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    },
    payload: JSON.stringify(records),
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(url, options);
  checkResponse(response, "Update", tableName);
}

function checkResponse(response, actionType, tableName) {
  const code = response.getResponseCode();
  if (code >= 200 && code < 300) {
    Logger.log(`SUCCESS: ${actionType} completed for ${tableName}.`);
  } else {
    Logger.log(`FAILED: ${actionType} for ${tableName}. Code: ${code}, Response: ${response.getContentText()}`);
  }
}

/**
 * Converts a sheet row array into a JSON object, formatting dates properly.
 */
/**
 * Converts a sheet row array into a JSON object, formatting dates 
 * and parsing nested JSON arrays/objects properly.
 */
/**
 * Converts a sheet row array into a JSON object, formatting dates 
 * and parsing nested JSON arrays/objects properly.
 */
function rowArrayToObject(headers, row) {
  const out = {};
  headers.forEach((h, i) => {
    let cellValue = row[i];
    
    if (cellValue == null || cellValue === '') {
      out[h] = null; // Send actual null to DB instead of empty string
    } else if (Object.prototype.toString.call(cellValue) === '[object Date]') {
      
      // Formats the Date object exactly as dd-MM-yyyy with leading zeros
      // (e.g., 22-06-1993)
      out[h] = Utilities.formatDate(cellValue, Session.getScriptTimeZone(), "yyyy-MM-dd"); 
      
    } else {
      // Convert to string to check its contents
      let strVal = String(cellValue).trim();
      
      // Detect if the cell contains a JSON array [...] or object {...}
      if ((strVal.startsWith('[') && strVal.endsWith(']')) || 
          (strVal.startsWith('{') && strVal.endsWith('}'))) {
        try {
          out[h] = JSON.parse(strVal);
          return; // Move to the next column
        } catch (e) {
          // If it fails to parse, safely fall through to standard text
        }
      }
      
      // Default: Send as standard text
      out[h] = strVal;
    }
  });
  return out;
}
```