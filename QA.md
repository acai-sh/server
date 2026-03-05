# Nav
* [ ] User profile icon in top left of header (button that toggles the settings/logout dropdown) is uneven (not centered)
* [ ] We can remove the default phoenix layout container / header, which shows email / settings / logout - this is redundant now
* [ ] We can move the logo.svg into the very top left, top of left nav panel above the team dropdown
* [ ] We need an intuitive way to get back out to the /teams list view once we've already entered a team.
* [ ] The team dropdown is not working. It doesn't do anything. Make sure we fix this in tests too, tests should not be passing.
* [ ] add a new requirement to the feature.yaml that we show the dark/light/system mode toggle - the default one for phoenix works great just reuse it (its currently visible on /teams list but needs to be moved to the nav or somewhere)
* [ ] The top level item should link me to the product overview, right now it just toggles the dropdown.

# teams-list
* [ ] Nav panel and header is not visible, so once we remove the phoenix default layout (see above) we won't be able to access user settings or logout in this view.
* [ ] Teams with long team names that wrap cause card to grow larger within the same row, which looks uneven. I would be happy with full-width cards since the number of teams is usually limited

# teams-view
* [ ] Add a section called Products that renders product cards which are hyperlinks, similar to the top level nav items, and they take you to product-view - make sure to update the spec with this new requirement too

# implementation-view
* [ ] The breadcrumb does not work, I can open the links to the higher order product or feature in new tabs (The urls look correct), but clicking locally doesn't work - just times out. Remember, the phoenix docs say this:
```
<.link href={...}> and redirect/2 are HTTP-based, work everywhere, and perform full page reloads
<.link navigate={...}> and push_navigate/2 work across LiveViews in the same session. They mount a new LiveView while keeping the current layout
<.link patch={...}> and push_patch/2 updates the current LiveView and sends only the minimal diff while also maintaining the scroll position
```
Other links are having issues too (link to user settings)

* [ ] I revised the requirement for implementation-view.CANONICAL_SPEC.1 - please fix it. Put this card and the tracked branches card first in the layout flow.
* [ ] For the coverage grids, just colored squares please, don't put the ACID in there. Add a hover tooltip that shows the ACID instead.
* [ ] I don't see any refs or test refs, 

# requirement-details
* [ ] The pre-wrap class on definition and note messes it up, awkard spacing, just remove it
* [ ] We should add `comment` section to details. I added this to the spec as requirement-details.DRAWER.7
 
# Misc
* [ ] I added favicon.svg and deleted favicon.ico please make sure favicon.svg is configured properly
* [ ] Everywhere in code, tests and seed data, I want to swap the 'implemented' status with 'completed'. So the canonical status journey is none, started, implemented, accepted, rejected
