import Footer from "@/components/wrapper/footer";
import Header from "@/components/wrapper/header";


export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <div>
      <Header />
      <main>
        {children}
      </main>
      <Footer />
    </div>
  );
}
