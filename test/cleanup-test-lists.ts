#!/usr/bin/env bun

/**
 * Cleanup script to delete test lists created by the test suite.
 * Uses AppleScript via osascript since EventKit doesn't support deleting lists.
 *
 * Usage: bun test/cleanup-test-lists.ts
 */

import {$} from 'bun';
import * as readline from 'node:readline';

const TEST_LIST_PREFIX = '[AR-MCP TEST]';

async function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase());
    });
  });
}

async function findTestLists(): Promise<string[]> {
  const appleScript = `
    tell application "Reminders"
      set testLists to {}
      repeat with aList in lists
        if name of aList starts with "${TEST_LIST_PREFIX}" then
          set end of testLists to name of aList
        end if
      end repeat
      return testLists as string
    end tell
  `;

  const result = await $`osascript -e ${appleScript}`.text();
  const trimmed = result.trim();

  if (!trimmed) {
    return [];
  }

  return trimmed.split(', ');
}

async function deleteLists(listNames: string[]): Promise<void> {
  for (const listName of listNames) {
    const appleScript = `
      tell application "Reminders"
        try
          delete (first list whose name is "${listName}")
          return "OK"
        on error errMsg
          return "ERROR: " & errMsg
        end try
      end tell
    `;

    const result = await $`osascript -e ${appleScript}`.text();
    const trimmed = result.trim();

    if (trimmed === 'OK') {
      console.log(`  Deleted: ${listName}`);
    } else {
      console.log(`  Failed: ${listName} - ${trimmed}`);
    }
  }
}

async function cleanupTestLists(): Promise<void> {
  console.log(
    `Searching for test lists prefixed with '${TEST_LIST_PREFIX}'...\n`,
  );

  try {
    const testLists = await findTestLists();

    if (testLists.length === 0) {
      console.log('No test lists found.');
      return;
    }

    console.log(`Found ${testLists.length} test list(s):`);
    for (const list of testLists) {
      console.log(`  - ${list}`);
    }
    console.log();

    const answer = await prompt('Delete these lists? [y/N] ');

    if (answer === 'y' || answer === 'yes') {
      console.log('\nDeleting...');
      await deleteLists(testLists);
      console.log('\nDone.');
    } else {
      console.log('\nCancelled. No lists were deleted.');
    }
  } catch (error) {
    console.error('Failed to run cleanup:', error);
    process.exit(1);
  }
}

cleanupTestLists();
