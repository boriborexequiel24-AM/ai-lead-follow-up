import Link from "next/link";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-md py-16 text-center">
      <h1 className="text-2xl font-semibold">Nothing here</h1>
      <p className="mt-2 text-stone-600">
        This page doesn&apos;t exist, or the conversation was deleted. Demo conversations are removed after 24 hours.
      </p>
      <Link href="/" className="mt-6 inline-block rounded-lg bg-copper-600 px-4 py-2 text-sm font-semibold text-white hover:bg-copper-700">
        Start a new request
      </Link>
    </div>
  );
}
