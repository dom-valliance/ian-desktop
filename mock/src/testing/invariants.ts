import type { Item, Snapshot } from '../domain/types.js';

/** Facts the schema cannot state (contract/README.md, step 4 of the D2 brief). Returns breaches. */
export function snapshotInvariants(snapshot: Snapshot): string[] {
  const breaches: string[] = [];
  const items = new Map(snapshot.items.map((item) => [item.id, item]));
  if (items.size !== snapshot.items.length) breaches.push('item ids are not unique');

  const needItem = (id: string, where: string): Item | undefined => {
    const item = items.get(id);
    if (!item) breaches.push(`${where} names ${id}, which is not in the snapshot`);
    return item;
  };

  for (const item of snapshot.items) {
    if (item.kind !== item.detail.kind)
      breaches.push(`${item.id}: kind ${item.kind} but detail ${item.detail.kind}`);
    if (item.kind === 'alert' && item.severity === undefined)
      breaches.push(`${item.id}: alert without severity`);
    if (item.kind !== 'alert' && item.severity !== undefined)
      breaches.push(`${item.id}: severity on a ${item.kind}`);
    if (
      !item.id.startsWith(
        {
          proposal: 'prop_',
          commitment_by: 'cmt_',
          commitment_to: 'cmt_',
          task: 'task_',
          alert: 'alrt_',
        }[item.kind],
      )
    ) {
      breaches.push(`${item.id}: id prefix does not match ${item.kind}`);
    }
  }

  const { today, views } = snapshot;
  const unitIds = new Set(today.field.units.map((unit) => unit.id));
  if (today.field.units.length > 5) breaches.push('more than five field units');
  const last = today.field.units.at(-1);
  if (today.field.units.some((unit) => unit.id === 'other') && last?.id !== 'other') {
    breaches.push('Other is not the last unit');
  }
  for (const cell of today.field.cells) {
    if (!unitIds.has(cell.unitId)) breaches.push(`cell unit ${cell.unitId} is not in field.units`);
    const cellItems = cell.itemIds.map((id) => needItem(id, 'a field cell'));
    const first = cellItems[0];
    if (first && first.kind !== cell.kind)
      breaches.push(`cell ${cell.unitId}/${cell.horizon}: kind is not the first item's`);
    for (const item of cellItems) {
      if (item && item.horizon !== cell.horizon)
        breaches.push(`${item.id}: in a ${cell.horizon} cell but horizon ${item.horizon}`);
    }
    const pressures = cellItems.map((item) => item?.pressure ?? 0);
    if (pressures.some((p, i) => i > 0 && p > (pressures[i - 1] ?? 1))) {
      breaches.push(`cell ${cell.unitId}/${cell.horizon}: items are not highest pressure first`);
    }
  }
  for (const group of today.lists.week) {
    if (!unitIds.has(group.unitId))
      breaches.push(`week group unit ${group.unitId} is not in field.units`);
    group.itemIds.forEach((id) => needItem(id, 'a week group'));
  }
  for (const group of today.lists.later) {
    if (!unitIds.has(group.unitId))
      breaches.push(`later group unit ${group.unitId} is not in field.units`);
  }
  today.lists.now.forEach((id) => needItem(id, 'lists.now'));
  today.orbit.itemIds.forEach((id) => needItem(id, 'the orbit'));

  const nowCount = today.lists.now.length;
  if (today.orbit.nowCount !== nowCount) breaches.push('orbit.nowCount differs from lists.now');
  if (today.orbit.itemIds.length > 5) breaches.push('more than five orbit items');
  if (today.orbit.overflow !== Math.max(0, nowCount - 5)) breaches.push('orbit.overflow is wrong');
  if (today.orbit.median < 1) breaches.push('orbit.median is below 1');
  const todayItems = snapshot.items.filter(
    (item) =>
      !(
        (item.detail.kind === 'commitment_by' || item.detail.kind === 'commitment_to') &&
        item.detail.toConfirm
      ),
  );
  if (today.orbit.load !== todayItems.length) breaches.push('orbit.load is not the open count');
  const urgent = todayItems.filter(
    (item) => item.attention === 'urgent' || item.attention === 'stop',
  ).length;
  if (today.orbit.urgentCount !== urgent) breaches.push('orbit.urgentCount is wrong');

  const grouped = [
    ...views.proposals.flatMap((group) => group.itemIds),
    ...views.commitments.owedByMe,
    ...views.commitments.owedToMe,
    ...views.commitments.toConfirm,
    ...views.tasks.flatMap((section) => section.groups.flatMap((group) => group.itemIds)),
    ...views.alerts.flatMap((group) => group.itemIds),
  ];
  grouped.forEach((id) => needItem(id, 'the views'));
  if (new Set(grouped).size !== grouped.length) breaches.push('an item sits in two view groups');
  if (grouped.length !== snapshot.items.length) breaches.push('the views do not cover every item');
  if (
    views.alerts[0] &&
    snapshot.items.some((i) => i.severity === 'P0') &&
    views.alerts[0].id !== 'P0'
  ) {
    breaches.push('P0 alerts are not first');
  }
  if (views.counts.agents !== snapshot.agents.agents.length)
    breaches.push('views.counts.agents is wrong');
  return breaches;
}
