// mrkvqv direct Home command. Loaded only into browser chrome by local AutoConfig.
(() => {
  'use strict';
  if (!window.gBrowser || !window.BrowserCommands || window.MrkvqvHome) return;
  const file = Services.dirsvc.get('Home', Ci.nsIFile);
  for (const part of ['.config','zen-startpage','startpage.html']) file.append(part);
  const homeURL = Services.io.newFileURI(file).spec;
  const browser = window.gBrowser;
  const original = window.BrowserCommands.home;
  let openingTab = null;

  function isHome(tab) {
    if (!tab?.isConnected || tab.closing) return false;
    const url = tab.linkedBrowser?.currentURI?.spec;
    if (url === homeURL) return true;
    if (tab === openingTab && url === 'about:blank') return true;
    if (tab.hasAttribute('pending')) {
      try { return window.SessionStore.getLazyTabValue(tab,'url') === homeURL; }
      catch { return false; }
    }
    return false;
  }

  function mark(tab) {
    tab.toggleAttribute('mrkvqv-home',isHome(tab));
  }

  function existingHome() {
    // Zen's browser.tabs contains only the active space. The sidebar tree spans all spaces.
    const homes = Array.from(browser.tabContainer.querySelectorAll('tab.tabbrowser-tab')).filter(isHome);
    const keep = homes[0];
    // One-time legacy/manual duplicates: only this exact file in this window.
    for (const duplicate of homes.slice(1)) browser.removeTab(duplicate,{animate:false});
    if (keep) mark(keep);
    return keep;
  }

  function showHome(event) {
    if (event?.button === 2) return;
    event?.preventDefault();
    let tab = existingHome();
    if (!tab) {
      tab = browser.addTab(homeURL,{
        triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal(),
        skipAnimation:true,relatedToCurrent:false
      });
      openingTab = tab;
      tab.setAttribute('mrkvqv-home','true');
    }
    if (tab.pinned) browser.unpinTab(tab);
    const spaces = window.gZenWorkspaces;
    if (spaces?.activeWorkspace && tab.getAttribute('zen-workspace-id') !== spaces.activeWorkspace) {
      spaces.moveTabToWorkspace(tab,spaces.activeWorkspace);
    }
    if (tab.hidden) browser.showTab(tab);
    browser.selectedTab = tab;
    tab.linkedBrowser.focus();
    return tab;
  }

  window.BrowserCommands.home = function(event) {
    // Keep native behavior if the user later chooses a different homepage.
    if (window.HomePage.get(window) !== homeURL) return original.call(this,event);
    return showHome(event);
  };
  const progress = {
    onLocationChange(contentBrowser) {
      const tab = browser.getTabForBrowser(contentBrowser);
      if (!tab) return;
      if (tab === openingTab && contentBrowser.currentURI?.spec !== 'about:blank') openingTab = null;
      mark(tab);
    }
  };
  browser.addTabsProgressListener(progress);
  const onRestored = event => mark(event.target);
  browser.tabContainer.addEventListener('SSTabRestored',onRestored);
  const onSessionRestored = () => existingHome();
  Services.obs.addObserver(onSessionRestored,'sessionstore-windows-restored');
  window.addEventListener('unload',() => {
    Services.obs.removeObserver(onSessionRestored,'sessionstore-windows-restored');
    browser.removeTabsProgressListener(progress);
    browser.tabContainer.removeEventListener('SSTabRestored',onRestored);
  },{once:true});
  existingHome();
  window.MrkvqvHome = Object.freeze({homeURL,showHome});
})();
