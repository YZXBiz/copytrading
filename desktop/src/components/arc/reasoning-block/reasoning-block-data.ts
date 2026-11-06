/** Sample reasoning for the self-playing preview. People, numbers and dates are realistic samples (October 2026). */
export interface ReasoningStep {
  /** Short step heading, such as "Tracing the retry path". Optional: untitled steps render as plain paragraphs. */
  title?: string;
  /** The step's reasoning. Separate paragraphs with a blank line. */
  text: string;
}

export interface ReasoningSample {
  model: string;
  steps: ReasoningStep[];
}

export const reasoningSamples: ReasoningSample[] = [
  {
    model: "Claude Opus 5.5",
    steps: [
      { title: "Reading the webhook handler", text: "The handler in api/billing/webhook.ts verifies the signature, then calls fulfillOrder for every invoice.paid event. Nothing records which events were already handled, so a redelivered event runs the whole path a second time." },
      { title: "Checking when Stripe retries", text: "Stripe redelivers an event when the endpoint times out or answers with an error. The logs for Oct 23 show fulfillOrder taking 11.4s on average, because the PDF receipt renders inline before the handler responds." },
      { title: "Tracing the second charge", text: "All 37 double charges line up with a redelivery. Each retry calls createUsageCharge again with an idempotency key built from Date.now(), so Stripe sees a brand new request instead of a repeat." },
      { title: "Choosing a fix", text: "Record event.id in processed_events inside the same transaction, derive the idempotency key from the invoice id, and move the receipt render to a queue so the handler answers in well under a second." },
    ],
  },
  {
    model: "Claude Sonnet 5.5",
    steps: [
      { title: "Checking calendars", text: "Of the 14 people invited to the Zurich offsite, 11 are free on Nov 12. Priya Raman and Marco Bianchi are at KubeCon that week, and Lena Vogel is out until Nov 14." },
      { title: "Comparing venue options", text: "Kraftwerk holds the main room until Oct 31 for CHF 4,200. Moving the date keeps the price, but it needs a fresh deposit of CHF 800 by Friday." },
      { title: "Weighing the trade off", text: "Nov 19 works for all 14 people and the room is free that day. One extra week costs nothing and keeps Priya, who runs the roadmap session the offsite is built around." },
      { title: "Drafting the answer", text: "Recommend Nov 19, name the three people Nov 12 would leave out, and offer to send the calendar update and the venue email together." },
    ],
  },
  {
    model: "Claude Fable 5.1",
    steps: [
      { title: "Splitting churn by plan", text: "Team churn rose from 2.1% in August to 3.4% in September, while Pro and Enterprise stayed flat. The spike sits in one plan, not across the whole base." },
      { title: "Lining it up with releases", text: "Seat based pricing shipped on Sep 9. Of the 61 Team accounts that cancelled, 44 had five or more inactive seats and saw their invoice grow by at least 30%." },
      { title: "Reading the exit survey", text: "Price is the top reason at 52%, and 18 responses mention paying for seats nobody uses. Only 4 mention a competitor by name." },
      { title: "Forming the answer", text: "The spike is mostly the pricing change landing on accounts with idle seats. Suggest removing seats inactive for 60 days automatically and emailing the 112 Team accounts that match the same pattern." },
    ],
  },
];
