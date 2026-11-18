// Slack layout for a price waiting for the owner's approval. Pasted into the
// n8n Code nodes by scripts/build_n8n_workflows.py, so workflow 1 (posting
// the draft) and workflow 3 (showing the outcome) always look the same.

function whoLine(lead) {
  const contact = [lead.email, lead.phone].filter(Boolean).join(', ') || 'no contact';
  return `${lead.name || 'Unknown'} (${contact}, zip ${lead.zip || 'unknown'})`;
}

function priceApprovalBlocks(p, outcome) {
  const quote = text => String(text || '').split('\n').map(line => '>' + line).join('\n');
  const blocks = [
    { type: 'section', text: { type: 'mrkdwn', text: `:moneybag: *Price waiting for approval*\n${p.who}\n${p.summary || ''}` } },
    { type: 'section', text: { type: 'mrkdwn', text: `*Draft reply to the customer*\n${quote(p.reply)}` } },
  ];
  if (outcome) {
    blocks.push({ type: 'context', elements: [{ type: 'mrkdwn', text: outcome }] });
  } else {
    blocks.push({
      type: 'actions',
      elements: [
        { type: 'button', style: 'primary', action_id: 'approve_price', value: String(p.approval_id),
          text: { type: 'plain_text', text: 'Approve and send' } },
        { type: 'button', style: 'danger', action_id: 'reject_price', value: String(p.approval_id),
          text: { type: 'plain_text', text: 'Reject' },
          confirm: {
            title: { type: 'plain_text', text: 'Reject this price?' },
            text: { type: 'mrkdwn', text: 'Nothing is sent to the customer and the lead is handed to you.' },
            confirm: { type: 'plain_text', text: 'Reject' },
            deny: { type: 'plain_text', text: 'Cancel' },
          } },
      ],
    });
  }
  return blocks;
}
