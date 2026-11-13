// One toolbar action: read the page address, title and selection, hand them to the app's
// native handler, and show only ok or failed. Nothing is sent to any server from here.

// Runs inside the page, so it must not use anything from this file.
function readPage() {
  return { url: location.href, title: document.title, selection: String(getSelection()) };
}

browser.action.onClicked.addListener(async (tab) => {
  let ok = false;
  try {
    const hits = await browser.scripting.executeScript({ target: { tabId: tab.id }, func: readPage });
    // Safari ignores the first argument and delivers the message to the containing app's handler.
    const reply = await browser.runtime.sendNativeMessage("application.id", hits[0].result);
    ok = Boolean(reply && reply.ok);
  } catch (error) {
    ok = false;
  }
  await browser.action.setBadgeText({ text: ok ? "ok" : "!", tabId: tab.id });
  // Best effort: the badge may stay if Safari stops this worker first.
  setTimeout(() => browser.action.setBadgeText({ text: "", tabId: tab.id }), 3000);
});
