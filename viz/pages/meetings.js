// meetings page — master-detail over team meetings, unified onto
// patterns/master-detail (Fase 0 paso 4): the meetings-table master block
// over the `meetings` source + the meeting-detail report panel. The ~140
// hand-rolled lines this page used to carry live in blocks/meetings-table.js
// now — the pattern owns all the wiring.

const pattern = require("../patterns/master-detail");
const meetingsTable = require("../blocks/meetings-table");
const meetingDetail = require("../blocks/meeting-detail");

function renderMeetings(ui) {
  return pattern.render(ui, {
    master: { block: meetingsTable, source: "meetings" },
    detail: { block: meetingDetail },
  });
}

module.exports = {
  id: "meetings",
  manifest: { consumes: "rows", overridable: meetingsTable.manifest.overridable },
  render: renderMeetings,
};
